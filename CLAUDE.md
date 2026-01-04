# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an educational Infrastructure as Code (IaC) project that deploys a complete Active Directory domain environment on OpenStack using OpenTofu (Terraform) and Ansible. It creates Windows domain controllers, Windows member servers, and Linux member servers, all integrated into a CDT.local domain.

## Key Architecture Principles

### Two-Stage Deployment Model
1. **Infrastructure Provisioning (OpenTofu)**: Creates VMs, networks, floating IPs, and security groups
2. **Configuration Management (Ansible)**: Configures domain services, joins machines to domain, creates users

### Dynamic Inventory Generation
The `import-tofu-to-ansible.py` script bridges OpenTofu and Ansible by reading `tofu output -json` and generating `ansible/inventory.ini`. This creates dynamic groups:
- `[windows_dc]` - First Windows VM (always the domain controller)
- `[windows_members]` - Remaining Windows VMs (domain members)
- `[linux_members]` - All Linux VMs (domain members)

### IP Address Scheme
- **Windows VMs**: `10.10.10.21`, `10.10.10.22`, `10.10.10.23` (first VM is DC)
- **Linux VMs**: `10.10.10.31`, `10.10.10.32`, `10.10.10.33`, `10.10.10.34`
- All VMs get floating IPs for external access via SSH jump host

### Network Access Pattern
All SSH and Ansible connections route through a jump host (`sshjump@ssh.cyberrange.rit.edu`) configured in `ansible/ansible.cfg`. WinRM connections use SOCKS5 proxy through the same jump host.

## Common Commands

### Initial Setup and Deployment
```bash
# Check prerequisites, credentials, and initialize OpenTofu
# (This automatically runs 'tofu init' for you)
./quick-start.sh

# Optional: Run linters before deployment
./check.sh

# Load OpenStack credentials (required before tofu commands)
source app-cred-openrc.sh

# Deploy infrastructure
cd opentofu
tofu plan   # Preview changes
tofu apply  # Deploy infrastructure

# Generate Ansible inventory from OpenTofu outputs
cd ..
python3 import-tofu-to-ansible.py

# Configure all servers
cd ansible
ansible-playbook -i inventory.ini site.yml
```

### Working with OpenTofu
```bash
# IMPORTANT: Always source credentials first!
source app-cred-openrc.sh

cd opentofu
tofu init                    # Initialize (only if adding/updating providers)
tofu plan                    # Preview changes
tofu apply                   # Apply changes
tofu destroy                 # Destroy all infrastructure
tofu output -json            # View outputs in JSON (used by Python script)
tofu taint <resource>        # Mark resource for rebuild
tofu state list              # List all resources in state
tofu show                    # Show current state

# Note: quick-start.sh automatically runs 'tofu init' during setup
```

### Working with Ansible
```bash
cd ansible

# Run all playbooks in sequence
ansible-playbook -i inventory.ini site.yml

# Run individual playbooks
ansible-playbook -i inventory.ini setup-domain-controller.yml
ansible-playbook -i inventory.ini join-windows-domain.yml
ansible-playbook -i inventory.ini join-linux-domain.yml
ansible-playbook -i inventory.ini create-domain-users.yml

# Test connectivity
ansible all -i inventory.ini -m ping
ansible windows -i inventory.ini -m ansible.windows.win_ping
ansible debian -i inventory.ini -m ping

# Run with increased verbosity
ansible-playbook -i inventory.ini site.yml -vvv

# Limit execution to specific hosts
ansible-playbook -i inventory.ini --limit cdt-win-1 setup-domain-controller.yml

# Check mode (dry run)
ansible-playbook -i inventory.ini --check site.yml
```

### Rebuilding Individual VMs
```bash
# Rebuild and reconfigure a single VM by IP
./rebuild-vm.sh <internal_ip or floating_ip>

# Examples:
./rebuild-vm.sh 10.10.10.21     # Rebuild DC by internal IP
./rebuild-vm.sh 100.65.4.55     # Rebuild by floating IP
```

### Inventory Management
```bash
# Regenerate inventory after OpenTofu changes
python3 import-tofu-to-ansible.py

# With custom paths
python3 import-tofu-to-ansible.py opentofu ansible inventory.ini
```

## Critical File Locations

### OpenTofu Files
- `opentofu/main.tf` - Provider configuration with OpenStack credentials
- `opentofu/variables.tf` - Configurable parameters (VM counts, hostnames, etc.)
- `opentofu/instances.tf` - VM definitions with conditional hostname logic
- `opentofu/network.tf` - Network, subnet, and router configuration
- `opentofu/security.tf` - Security groups and firewall rules
- `opentofu/outputs.tf` - Outputs consumed by import script
- `opentofu/windows-userdata.ps1` - Cloud-init for Windows (enables WinRM)
- `opentofu/debian-userdata.yaml` - Cloud-init for Linux

### Ansible Files
- `ansible/site.yml` - Main orchestration playbook (imports all others)
- `ansible/setup-domain-controller.yml` - Promotes first Windows VM to DC
- `ansible/join-windows-domain.yml` - Joins Windows members to domain
- `ansible/join-linux-domain.yml` - Joins Linux members using realmd/SSSD
- `ansible/create-domain-users.yml` - Creates domain users and SSH access
- `ansible/activate-windows-kms.yml` - Activates Windows with KMS server
- `ansible/setup-rdp-linux.yml` - Installs xrdp on Linux VMs
- `ansible/setup-rdp-windows.yml` - Configures RDP on Windows VMs
- `ansible/ansible.cfg` - SSH jump host and connection settings
- `ansible/inventory.ini` - Auto-generated by import script (do not edit manually)

### Utility Scripts
- `import-tofu-to-ansible.py` - Bridges OpenTofu and Ansible
- `rebuild-vm.sh` - Rebuilds and reconfigures individual VMs
- `quick-start.sh` - Prerequisites checker and setup helper
- `check.sh` - Runs tflint and ansible-lint

## Important Behavioral Notes

### Custom Hostnames
VM names can be customized via `windows_hostnames` and `debian_hostnames` list variables in `variables.tf`. The conditional logic in `instances.tf:12` and `instances.tf:37`:
```hcl
name = length(var.windows_hostnames) > count.index ? var.windows_hostnames[count.index] : "cdt-win-${count.index + 1}"
```
If the list is shorter than the count, remaining VMs use auto-generated names (e.g., `cdt-win-3`).

### Domain Controller Assignment
The **first Windows VM** in the inventory is always the domain controller. This is determined by array order, not by IP or name. The `import-tofu-to-ansible.py` script creates the `[windows_dc]` group with `windows_names[0]`.

### Playbook Execution Order in site.yml
1. Setup Domain Controller (first Windows VM)
2. Join Windows Members (remaining Windows VMs)
3. Activate Windows (all Windows VMs)
4. Join Linux Members (all Linux VMs)
5. Create Domain Users (on DC, enables SSH for users)
6. Setup RDP on Linux
7. Setup RDP on Windows

When creating new playbooks, add them to `site.yml` using `import_playbook` to include them in the standard workflow.

### Credential Management

#### OpenStack Credentials (Simple Setup)
OpenStack credentials are managed through a single downloaded file:

**Setup Process (First Time)**:
1. Go to OpenStack Dashboard: https://openstack.cyberrange.rit.edu
2. Navigate to: Identity → Application Credentials
3. Click "Create Application Credential"
   - Name: `cdt-automation` (or any name)
   - Click "Create Application Credential"
4. On the success page, click **"Download openrc file"**
   - This downloads a shell script like `app-cred-USERNAME-PROJECT-openrc.sh`
5. Move the file to your project root directory:
   ```bash
   mv ~/Downloads/app-cred-*-openrc.sh /path/to/cdt-automation/
   ```
6. Run `./quick-start.sh` - it will auto-detect and rename the file to `app-cred-openrc.sh`

**Usage**:
- Before running any `tofu` commands, always source the credentials:
  ```bash
  source app-cred-openrc.sh
  ```
- The file sets environment variables that OpenTofu/Terraform reads automatically
- File is automatically gitignored (pattern: `app-cred*openrc.sh`)
- Works for both OpenTofu and OpenStack CLI commands

#### SSH Keys
- SSH key must be RSA format (`~/.ssh/id_rsa`) for Windows compatibility
- Must be imported into OpenStack Dashboard (Compute → Key Pairs)
- Configure keypair name in `opentofu/variables.tf`

#### Default VM Credentials
- Linux: `cyberrange:Cyberrange123!`
- Windows: `cyberrange:Cyberrange123!`
- Domain Admin: `Administrator:Cyberrange123!`
- Domain Users: `UserPass123!`

### SSH Jump Host Configuration
All connections route through `sshjump@ssh.cyberrange.rit.edu` via SSH ProxyJump. This is configured in:
- `ansible/ansible.cfg` - SSH args with `-J` flag
- WinRM uses SOCKS5 proxy: `ansible_winrm_proxy=socks5h://ssh.cyberrange.rit.edu:1080`

## Modifying Infrastructure

### Changing VM Counts
Edit `opentofu/variables.tf`:
```hcl
variable "windows_count" { default = 5 }  # Change from 3 to 5
variable "debian_count" { default = 6 }   # Change from 4 to 6
```
Then:
```bash
source app-cred-openrc.sh
cd opentofu && tofu apply
cd .. && python3 import-tofu-to-ansible.py
```

### Adding Custom Playbooks
1. Create playbook in `ansible/` directory
2. Add to `ansible/site.yml` with `import_playbook` directive
3. Use dynamic groups (`windows_dc`, `windows_members`, `linux_members`) instead of hardcoded hostnames

### IP Address Constraints
Fixed IPs are assigned via string interpolation in `instances.tf`:
- Windows: `10.10.10.2${count.index + 1}` (21, 22, 23...)
- Linux: `10.10.10.3${count.index + 1}` (31, 32, 33...)

To change the scheme, edit both the interpolation and the subnet CIDR in `variables.tf`.

## Troubleshooting Context

### State Management
OpenTofu state is stored locally in `opentofu/terraform.tfstate`. The `rebuild-vm.sh` script uses `tofu taint` to force recreation of specific VMs without destroying others.

### Connectivity Testing
Windows VMs take ~15 minutes to boot (cloud-init, WinRM setup). Linux VMs take ~5 minutes. The `rebuild-vm.sh` script handles these timeouts automatically.

### Inventory Regeneration
Always regenerate inventory after OpenTofu changes. The script reads live state, so manual edits to `inventory.ini` will be overwritten.

### Linting
`check.sh` runs tflint (OpenTofu) and ansible-lint. These are optional but recommended before deployment.

## Domain Details

- **Domain Name**: CDT.local
- **Domain Controller**: First Windows VM (10.10.10.21 by default)
- **Created Users**: jdoe, asmith, bwilson, mjohnson, dlee
- **Linux Admins**: jdoe, asmith (sudo access)
- **SSH Format**: `username@CDT.local@<host_ip>`
- **RDP**: Enabled on port 3389 for both Windows (native) and Linux (xrdp with LXQT)
