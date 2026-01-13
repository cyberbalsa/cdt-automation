# CDT OpenStack Automation Project

**A Student Guide to Infrastructure as Code with OpenTofu and Ansible**

This project demonstrates how to bootstrap a complete cloud infrastructure on OpenStack using Infrastructure as Code (IaC) principles. You'll learn to deploy virtual machines with OpenTofu (Terraform) and configure them with Ansible to create a functional Active Directory domain environment.

## Learning Objectives

By completing this project, you will:
- Understand OpenStack cloud infrastructure concepts
- Learn Infrastructure as Code using OpenTofu (Terraform)
- Master configuration management with Ansible
- Deploy and manage a multi-server domain environment
- Practice DevOps automation workflows

## Prerequisites

### Required Knowledge
- Basic Linux command line skills
- Understanding of networking concepts (subnets, routers, firewalls)
- Familiarity with YAML and basic programming concepts
- SSH and remote server management

### Required Software
- OpenTofu (Terraform alternative) - [Installation Guide](https://opentofu.org/docs/intro/install/)
- Ansible - `sudo apt install ansible` (Ubuntu/Debian) or `brew install ansible` (macOS)
- SSH client
- Git

### Access Requirements
- OpenStack account with project access
- SSH key pair registered in OpenStack
- Application credentials for API access

## Project Architecture

This project creates a complete infrastructure consisting of:

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenStack Project                        │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │   External      │    │        Private Network          │ │
│  │   Network       │────│        (10.10.10.0/24)          │ │
│  │   (MAIN-NAT)    │    │                                 │ │
│  └─────────────────┘    │  ┌─────────────────────────────┐│ │
│                         │  │    Domain Controller        ││ │
│                         │  │    10.10.10.21 (Windows)    ││ │
│                         │  └─────────────────────────────┘│ │
│                         │                                 │ │
│                         │  ┌─────────────────────────────┐│ │
│                         │  │    Windows Servers          ││ │
│                         │  │    10.10.10.22-23           ││ │
│                         │  └─────────────────────────────┘│ │
│                         │                                 │ │
│                         │  ┌─────────────────────────────┐│ │
│                         │  │    Linux Servers            ││ │
│                         │  │    10.10.10.31-34           ││ │
│                         │  └─────────────────────────────┘│ │
│                         └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Infrastructure Components
- **Network**: Private subnet with router and external connectivity
- **Windows Domain Controller**: Manages Active Directory (CDT.local)
- **Windows Member Servers**: Domain-joined Windows Server 2022 instances
- **Linux Member Servers**: Domain-joined Debian servers with SSH access
- **Floating IPs**: External access to all servers
- **Security Groups**: Firewall rules for proper service access

## Quick Start Guide

### Step 1: Clone and Setup
```bash
# Clone the repository
git clone <your-repo-url>
cd cdt-automation

# Verify prerequisites
tofu version
ansible --version
ssh-keygen -l -f ~/.ssh/id_rsa.pub  # Verify your SSH key
```

### Step 2: Download and Configure OpenStack Credentials

#### A. Create Application Credentials in OpenStack Dashboard
1. **Login to OpenStack Dashboard**: https://openstack.cyberrange.rit.edu
2. **Navigate to API Access**: Identity → Application Credenitials
3. **Create Application Credentials**:
   - Click "Create Application Credential"
   - Give it a descriptive name (e.g., "cdt-automation")
   - Leave expiration date empty for no expiration
   - Click "Create Application Credential"
4. **Download the credentials**: 
   - **IMPORTANT**: Save the ID and Secret immediately - you cannot retrieve the secret later!
   - Copy the Application Credential ID and Secret

#### C. Update OpenTofu Configuration
```bash
# Edit main.tf with your credentials
vim opentofu/main.tf
# Update the application_credential_id and application_credential_secret values
```

### Step 3: Customize Variables (Optional)
Edit `opentofu/variables.tf` to modify:
- Number of Windows/Linux servers
- Instance flavors (sizes)
- Network configuration
- SSH key name
- Custom hostnames for VMs

#### Setting Custom Hostnames

By default, VMs are named with auto-generated names like `cdt-win-1`, `cdt-win-2`, etc. You can customize these names using the `windows_hostnames` and `debian_hostnames` variables.

**Option 1: Edit variables.tf directly**
```hcl
variable "windows_hostnames" {
  type    = list(string)
  default = ["dc01", "fs01", "web01"]
}

variable "debian_hostnames" {
  type    = list(string)
  default = ["jumphost", "mail-server", "db-server", "web-server"]
}
```

**Option 2: Mix custom and auto-generated names**
```hcl
# Only customize first 2 Windows VMs
windows_count = 5
windows_hostnames = ["dc01", "dc02"]
# Result: dc01, dc02, cdt-win-3, cdt-win-4, cdt-win-5

# Leave all Linux VMs with default names
debian_count = 4
debian_hostnames = []
# Result: cdt-debian-1, cdt-debian-2, cdt-debian-3, cdt-debian-4
```

**Important Notes:**
- If you provide fewer hostnames than the count, remaining VMs use auto-generated names
- Empty list `[]` (default) means all VMs use auto-generated names
- Hostname must match the number of VMs or be shorter (not longer)

### Step 4: Deploy Infrastructure
```bash
cd opentofu

# Initialize OpenTofu
tofu init

# Review the planned changes
tofu plan

# Deploy the infrastructure
tofu apply
```

### Step 5: Generate Ansible Inventory
```bash
# Run the import script to automatically generate inventory from OpenTofu outputs
python3 import-tofu-to-ansible.py

# This creates ansible/inventory.ini with all VM details
```

### Step 6: Configure Servers with Ansible
```bash
# copy ansible directory to a remote server inside the network, use the 4th debian server for this.
# ssh -J sshproxy@ssh.cyberrange.rit.edu debian@100.65.X.X
sudo apt install ansible
cd ansible

# The inventory.ini was already generated in Step 5
# Run the complete setup
ansible-playbook -i inventory.ini site.yml
```

## Utility Scripts

### Automatic Inventory Generation

The `import-tofu-to-ansible.py` script automatically generates the Ansible inventory from OpenTofu outputs.

**Usage:**
```bash
python3 import-tofu-to-ansible.py [tofu_dir] [ansible_dir] [inventory_filename]
```

**What it does:**
1. Reads OpenTofu outputs (VM names, floating IPs, internal IPs)
2. Generates `inventory.ini` with proper groups
3. Creates dynamic groups:
   - `[windows_dc]` - First Windows VM (Domain Controller)
   - `[windows_members]` - Remaining Windows VMs
   - `[linux_members]` - All Linux VMs
4. Adds connection variables (passwords, WinRM config, etc.)

**When to run:**
- After initial `tofu apply`
- After changing VM counts (`tofu apply` with new variables)
- After rebuilding infrastructure

### Rebuild Individual VMs

The `rebuild-vm.sh` script allows you to rebuild and reconfigure a single VM without affecting others.

**Usage:**
```bash
./rebuild-vm.sh <internal_ip or floating_ip>
```

**Examples:**
```bash
# Rebuild using internal IP
./rebuild-vm.sh 10.10.10.21

# Rebuild using floating IP
./rebuild-vm.sh 100.65.4.55
```

**What it does:**
1. **Finds the VM** - Searches OpenTofu state for the provided IP
2. **Confirms rebuild** - Asks for confirmation before proceeding
3. **Taints resource** - Marks the VM for rebuild in OpenTofu
4. **Rebuilds VM** - Destroys and recreates only that specific VM
5. **Regenerates inventory** - Updates `inventory.ini` automatically
6. **Waits for boot** - Smart timeout based on OS:
   - Windows: 15 minutes (longer boot time)
   - Linux: 5 minutes
7. **Tests connectivity** - Uses `win_ping` for Windows, `ping` for Linux
8. **Runs playbooks** - Automatically configures based on VM role:
   - Domain Controller: `setup-domain-controller.yml`
   - Windows Members: `join-windows-domain.yml`
   - Linux Members: `join-linux-domain.yml` + `create-domain-users.yml`

**Use Cases:**
- VM is corrupted or misconfigured
- Testing configuration changes
- Domain controller issues
- Quick reset of a single server

**Example Output:**
```bash
$ ./rebuild-vm.sh 10.10.10.21
[INFO] Target IP: 10.10.10.21
[INFO] Fetching OpenTofu state...
[SUCCESS] Found VM: cdt-win-1 (type: windows, index: 0)
[WARNING] About to rebuild: cdt-win-1
Are you sure you want to rebuild this VM? (yes/no): yes
[INFO] Rebuilding VM with OpenTofu...
[INFO] Waiting for VM to come online...
[INFO] Detected Windows VM - using extended timeout (15 minutes)
[SUCCESS] VM is online and reachable!
[INFO] Running playbook: setup-domain-controller.yml
[SUCCESS] VM Rebuild and Configuration Complete!
```

## 📖 Detailed Learning Guide

### Understanding OpenTofu (Terraform)

OpenTofu is an Infrastructure as Code tool that lets you define cloud resources using declarative configuration files.

#### Key Files in `/opentofu/`:
- **`main.tf`**: Provider configuration and authentication
- **`variables.tf`**: Configurable parameters (like server counts, sizes)
- **`network.tf`**: Network infrastructure (VPC, subnets, routers)
- **`instances.tf`**: Virtual machine definitions
- **`outputs.tf`**: Information displayed after deployment

#### Key Concepts:
```hcl
# Resource Declaration
resource "openstack_compute_instance_v2" "my_server" {
  name        = "my-server-name"
  image_name  = "debian-trixie-amd64-cloud"
  flavor_name = "medium"
  
  network {
    uuid = openstack_networking_network_v2.my_net.id
  }
}

# Variable Usage
variable "server_count" {
  default = 3
  description = "Number of servers to create"
}

# Data Sources (read existing resources)
data "openstack_networking_network_v2" "external" {
  name = "MAIN-NAT"
}
```

### Understanding Ansible

Ansible automates server configuration using playbooks written in YAML.

#### Key Files in `/ansible/`:
- **`inventory.ini`**: Server lists and connection details
- **`site.yml`**: Main orchestration playbook that imports all other playbooks
- **`setup-domain-controller.yml`**: Windows AD setup
- **`join-windows-domain.yml`**: Windows domain joining
- **`join-linux-domain.yml`**: Linux domain integration
- **`create-domain-users.yml`**: User management

#### Key Concepts:
```yaml
# Task Definition
- name: Install package
  ansible.builtin.package:
    name: realmd
    state: present

# Conditional Execution
- name: Configure service
  ansible.builtin.service:
    name: sssd
    state: started
    enabled: yes
  when: ansible_os_family == "Debian"

# Variable Usage
- name: Create user
  ansible.builtin.user:
    name: "{{ item.username }}"
    password: "{{ item.password | password_hash('sha512') }}"
  loop: "{{ domain_users }}"

# Importing Playbooks (in site.yml)
- name: Setup Component
  import_playbook: setup-component.yml
```

**Important**: When creating new playbooks, add them to `site.yml` using `import_playbook` so they execute as part of the complete setup workflow.

## 🔧 Configuration Management

### OpenStack Authentication
The project uses Application Credentials for secure API access:

```bash
# In your openrc file
export OS_AUTH_TYPE=v3applicationcredential
export OS_APPLICATION_CREDENTIAL_ID="your-credential-id"
export OS_APPLICATION_CREDENTIAL_SECRET="your-credential-secret"
```

### Network Configuration
```hcl
# Creates isolated network
resource "openstack_networking_network_v2" "cdt_net" {
  name = "cdt-net"
}

# Subnet with specific CIDR
resource "openstack_networking_subnet_v2" "cdt_subnet" {
  cidr            = "10.10.10.0/24"
  dns_nameservers = ["129.21.3.17", "129.21.4.18"]
}
```

### Server Provisioning
The project creates:
- **3 Windows Servers** (configurable via `windows_count`)
- **4 Linux Servers** (configurable via `debian_count`)
- **Floating IPs** for external access
- **Cloud-init** for initial configuration

#### Custom VM Hostnames
You can customize VM names using the `windows_hostnames` and `debian_hostnames` list variables:

```hcl
# In variables.tf or terraform.tfvars
variable "windows_hostnames" {
  type        = list(string)
  default     = ["dc01", "web01", "app01"]
  description = "Custom hostnames for Windows VMs"
}

variable "debian_hostnames" {
  type        = list(string)
  default     = ["jumphost", "db01", "cache01", "monitor01"]
  description = "Custom hostnames for Debian VMs"
}
```

The implementation uses conditional logic in `instances.tf`:
```hcl
resource "openstack_compute_instance_v2" "windows" {
  count = var.windows_count
  name  = length(var.windows_hostnames) > count.index ? var.windows_hostnames[count.index] : "cdt-win-${count.index + 1}"
  # ... rest of configuration
}
```

This allows you to:
- Provide a full list of custom names
- Provide partial names (remaining VMs use auto-generated names)
- Use empty list for all auto-generated names (default behavior)

## Educational Exercises

### Beginner Level
1. **Modify Server Count**: Change `windows_count` and `debian_count` in variables
2. **Change Instance Size**: Modify `flavor_name` to use different VM sizes
3. **Network Customization**: Adjust the subnet CIDR range

### Intermediate Level
1. **Add New Server Type**: Create Ubuntu servers alongside Debian
2. **Security Groups**: Implement custom firewall rules
3. **Storage Volumes**: Attach additional storage to servers

### Advanced Level
1. **Multi-Region Deployment**: Deploy across multiple availability zones
2. **Load Balancer**: Add load balancing for web services
3. **Monitoring**: Integrate monitoring and logging solutions

## Troubleshooting Guide

### Common OpenTofu Issues

**Authentication Errors**:
```bash
# Verify credentials are loaded
env | grep OS_
# Check if main.tf has your actual credentials (not placeholders)
grep "YOUR_APPLICATION_CREDENTIAL" opentofu/main.tf
# If this shows matches, you need to replace the placeholder values!
```

**Missing Credentials Setup**:
If you see errors like "Invalid application credential" or "Authentication failed":
1. Verify you've downloaded credentials from OpenStack dashboard
2. Check that you've updated both the openrc file AND main.tf
3. Ensure credential ID and secret match exactly (no extra spaces/characters)

**Resource Conflicts**:
```bash
# Check existing resources
tofu state list
tofu show

# Import existing resources if needed
tofu import openstack_compute_instance_v2.windows[0] <instance-id>
```

**State Issues**:
```bash
# Backup and refresh state
cp terraform.tfstate terraform.tfstate.backup
tofu refresh
```

### Common Ansible Issues

**Connection Problems**:
```bash
# Test connectivity
ansible -i inventory.ini windows -m win_ping
ansible -i inventory.ini linux -m ping

# Debug connection
ansible-playbook -i inventory.ini site.yml -vvv
```

**Windows WinRM Issues**:
```powershell
# On Windows servers
winrm quickconfig
winrm set winrm/config/service/auth @{Basic="true"}
```

**SSH Key Problems**:
```bash
# Verify SSH access
ssh -i ~/.ssh/id_rsa debian@<floating-ip>

# Check key format
ssh-keygen -l -f ~/.ssh/id_rsa.pub
```

## Additional Resources

### Learning Materials
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Ansible Documentation](https://docs.ansible.com/)
- [OpenStack User Guide](https://docs.openstack.org/user-guide/)

### Advanced Topics
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Infrastructure as Code Patterns](https://infrastructure-as-code.com/)

### Community
- [OpenTofu Community](https://opentofu.org/community/)
- [Ansible Community](https://www.ansible.com/community)
- [OpenStack Community](https://www.openstack.org/community/)

## Contributing

This is an educational project! Contributions welcome:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit changes (`git commit -am 'Add educational content'`)
4. Push to branch (`git push origin feature/improvement`)
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Getting Help

If you encounter issues:

1. **Check the troubleshooting section** above
2. **Review logs**: 
   - OpenTofu: Check command output and state files
   - Ansible: Use `-vvv` flag for detailed logging
3. **Ask for help**: 
   - Create an issue in this repository
   - Ask in class or office hours
   - Consult documentation links above

Remember: Making mistakes is part of learning! Don't be afraid to experiment and break things in your learning environment.

---

**Happy Learning!**

*This project is designed for educational purposes to teach Infrastructure as Code concepts using real-world tools and practices.*
