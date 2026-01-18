# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an educational Infrastructure as Code (IaC) project that deploys a complete Active Directory domain environment on OpenStack using OpenTofu (Terraform) and Ansible. It creates Windows domain controllers, Windows member servers, and Linux member servers, all integrated into a CDT.local domain.

## Key Architecture Principles

### Two-Stage Deployment Model
1. **Infrastructure Provisioning (OpenTofu)**: Creates VMs, networks, floating IPs, and security groups
2. **Configuration Management (Ansible)**: Configures domain services, joins machines to domain, creates users

### Multi-Project Grey Team Architecture
This infrastructure supports attack/defend CTF competitions using OpenStack's multi-project capabilities:

**Three OpenStack Projects:**
- **Main Project (Grey Team)**: Owns the network, runs scoring infrastructure
- **Blue Project (Defenders)**: Blue Team VMs (Windows DC, members, Linux servers)
- **Red Project (Attackers)**: Red Team Kali attack machines

**RBAC Network Sharing:** The network lives in the main project and is shared with Blue and Red projects via RBAC policies. This allows all VMs to communicate on the same network (10.10.10.0/24) while maintaining project-level isolation for access control and quotas.

### Dynamic Inventory Generation
The `import-tofu-to-ansible.py` script bridges OpenTofu and Ansible by reading `tofu output -json` and generating `ansible/inventory/production.ini`. This creates dynamic groups:

**By Team:**
- `[scoring]` - Grey Team scoring servers
- `[blue_windows]` - Blue Team Windows VMs
- `[blue_linux]` - Blue Team Linux VMs
- `[red_team]` - Red Team Kali VMs

**By Role:**
- `[windows_dc]` - First Blue Windows VM (Domain Controller)
- `[blue_windows_members]` - Blue Windows VMs except DC
- `[blue_linux_members]` - Blue Linux VMs (join domain)

**Hierarchies:**
- `[windows:children]` - All Windows VMs (windows_dc + blue_windows_members)
- `[blue_team:children]` - All Blue Team VMs (blue_windows + blue_linux)
- `[linux_members:children]` - All Linux VMs (blue_linux + red_team + scoring)

### IP Address Scheme
- **Scoring VMs**: `10.10.10.11`, `10.10.10.12`, etc. (main project)
- **Blue Windows VMs**: `10.10.10.21`, `10.10.10.22`, `10.10.10.23` (first VM is DC)
- **Blue Linux VMs**: `10.10.10.31`, `10.10.10.32`, `10.10.10.33`, `10.10.10.34`
- **Red Kali VMs**: `10.10.10.41`, `10.10.10.42`, etc.
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
ansible-playbook playbooks/site.yml
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
ansible-playbook playbooks/site.yml

# Run individual playbooks
ansible-playbook playbooks/setup-domain-controller.yml
ansible-playbook playbooks/join-windows-domain.yml
ansible-playbook playbooks/join-linux-domain.yml
ansible-playbook playbooks/create-domain-users.yml

# Test connectivity
ansible all -m ping
ansible windows -m ansible.windows.win_ping
ansible debian -m ping

# Run with increased verbosity
ansible-playbook playbooks/site.yml -vvv

# Limit execution to specific hosts
ansible-playbook playbooks/setup-domain-controller.yml --limit cdt-win-1

# Check mode (dry run)
ansible-playbook playbooks/site.yml --check

# Use roles directly (if needed)
ansible-playbook -e "role_name=domain_controller" playbooks/setup-domain-controller.yml
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

# With custom paths (tofu_dir ansible_dir inventory_file)
python3 import-tofu-to-ansible.py opentofu ansible inventory/production.ini

# Note: The script now defaults to creating inventory/production.ini
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
**Playbooks:**
- `ansible/playbooks/site.yml` - Main orchestration playbook (imports all others)
- `ansible/playbooks/setup-domain-controller.yml` - Uses domain_controller role
- `ansible/playbooks/join-windows-domain.yml` - Joins Windows members to domain
- `ansible/playbooks/join-linux-domain.yml` - Uses linux_domain_member role
- `ansible/playbooks/create-domain-users.yml` - Uses domain_users role + SSH config
- `ansible/playbooks/activate-windows-kms.yml` - Activates Windows with KMS server
- `ansible/playbooks/setup-rdp-linux.yml` - Installs xrdp on Linux VMs
- `ansible/playbooks/setup-rdp-windows.yml` - Configures RDP on Windows VMs

**Roles:**
- `ansible/roles/domain_controller/` - Domain controller setup tasks
- `ansible/roles/linux_domain_member/` - Linux domain join tasks with handlers
- `ansible/roles/domain_users/` - Domain user and group creation tasks

**Configuration:**
- `ansible/ansible.cfg` - SSH jump host, inventory path, and connection settings
- `ansible/inventory/production.ini` - Auto-generated by import script (do not edit manually)
- `ansible/group_vars/all.yml` - Global variables (domain config, users)
- `ansible/group_vars/linux_members.yml` - Linux-specific variables (Kerberos, SSSD, SSH)
- `ansible/group_vars/windows.yml` - Windows-specific variables
- `ansible/group_vars/windows_dc.yml` - Domain controller-specific variables

### Utility Scripts
- `import-tofu-to-ansible.py` - Bridges OpenTofu and Ansible
- `rebuild-vm.sh` - Rebuilds and reconfigures individual VMs
- `quick-start.sh` - Prerequisites checker and setup helper
- `check.sh` - Runs tflint and ansible-lint

## Important Behavioral Notes

### Custom Hostnames
VM names can be customized via `blue_windows_hostnames` and `blue_linux_hostnames` list variables in `variables.tf`. The conditional logic in `instances.tf`:
```hcl
name = length(var.blue_windows_hostnames) > count.index ? var.blue_windows_hostnames[count.index] : "blue-win-${count.index + 1}"
```
If the list is shorter than the count, remaining VMs use auto-generated names (e.g., `blue-win-3`).

### Domain Controller Assignment
The **first Blue Windows VM** in the inventory is always the domain controller. This is determined by array order, not by IP or name. The `import-tofu-to-ansible.py` script creates the `[windows_dc]` group with `blue_windows_names[0]`.

### Ansible Directory Structure
The project follows standard Ansible best practices for easier collaboration:

```
ansible/
├── playbooks/          # All playbook files
│   ├── site.yml       # Main orchestration playbook
│   └── *.yml          # Individual playbooks
├── roles/             # Reusable role components
│   ├── domain_controller/
│   ├── linux_domain_member/
│   └── domain_users/
├── inventory/         # Inventory files
│   └── production.ini # Auto-generated from OpenTofu
├── group_vars/        # Group-specific variables
│   ├── all.yml       # Global variables
│   ├── linux_members.yml
│   ├── windows.yml
│   └── windows_dc.yml
├── ansible.cfg        # Ansible configuration
└── README.md         # Documentation
```

**Key Benefits:**
- **Roles**: Complex tasks (DC setup, Linux domain join, user creation) are modular and reusable
- **Group Variables**: Settings organized by host groups, easier to maintain
- **Separation**: Playbooks, roles, and inventory are clearly separated
- **Scalability**: Easy to add new roles and playbooks without cluttering the root directory

### Playbook Execution Order in playbooks/site.yml
1. **Validate Inventory** - Checks that required groups are populated
2. Setup Domain Controller (uses `domain_controller` role)
3. Join Windows Members (remaining Windows VMs)
4. Activate Windows (all Windows VMs)
5. Join Linux Members (uses `linux_domain_member` role)
6. Create Domain Users (uses `domain_users` role + SSH config)
7. Setup RDP on Linux
8. Setup RDP on Windows

When creating new playbooks, add them to `playbooks/site.yml` using `import_playbook` to include them in the standard workflow.

### Inventory Validation
The `site.yml` playbook automatically validates the inventory before execution. It checks that:
- Required groups (`windows`, `windows_dc`, `linux_members`) exist
- Each group contains at least one host

If validation fails, you'll see a helpful error message instructing you to run:
```bash
python3 import-tofu-to-ansible.py
```

This prevents common mistakes like running Ansible before generating the inventory from OpenTofu outputs.

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
- The file sets environment variables (`OS_APPLICATION_CREDENTIAL_ID`, `OS_APPLICATION_CREDENTIAL_SECRET`, etc.)
- The OpenStack provider in `main.tf` automatically reads these environment variables
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
# Scoring servers (Grey Team)
variable "scoring_count" { default = 1 }

# Blue Team VMs
variable "blue_windows_count" { default = 3 }  # First becomes DC
variable "blue_linux_count" { default = 4 }

# Red Team VMs
variable "red_kali_count" { default = 2 }
```
Then:
```bash
source app-cred-openrc.sh
cd opentofu && tofu apply
cd .. && python3 import-tofu-to-ansible.py
```

### Adding Custom Playbooks and Roles
**Creating a New Playbook:**
1. Create playbook in `ansible/playbooks/` directory
2. Add to `ansible/playbooks/site.yml` with `import_playbook` directive
3. Use dynamic groups (`windows_dc`, `windows_members`, `linux_members`) instead of hardcoded hostnames

**Creating a New Role:**
1. Create role directory structure:
   ```bash
   mkdir -p ansible/roles/my_role/{tasks,handlers,templates,files,defaults}
   ```
2. Create `ansible/roles/my_role/tasks/main.yml` with your tasks
3. Add handlers in `ansible/roles/my_role/handlers/main.yml` if needed
4. Define default variables in `ansible/roles/my_role/defaults/main.yml`
5. Use the role in a playbook:
   ```yaml
   - name: My Custom Configuration
     hosts: target_group
     roles:
       - my_role
   ```

**Best Practices:**
- Convert complex, multi-step configurations into roles
- Keep simple, one-off tasks as playbooks
- Store group-specific variables in `group_vars/`
- Use templates for configuration files that need variable substitution

### IP Address Constraints
Fixed IPs are assigned via string interpolation in `instances.tf`:
- Scoring: `10.10.10.1${count.index + 1}` (11, 12, 13...)
- Blue Windows: `10.10.10.2${count.index + 1}` (21, 22, 23...)
- Blue Linux: `10.10.10.3${count.index + 1}` (31, 32, 33...)
- Red Kali: `10.10.10.4${count.index + 1}` (41, 42, 43...)

To change the scheme, edit both the interpolation and the subnet CIDR in `variables.tf`.

## Troubleshooting Context

### State Management
OpenTofu state is stored locally in `opentofu/terraform.tfstate`. The `rebuild-vm.sh` script uses `tofu taint` to force recreation of specific VMs without destroying others.

### Connectivity Testing
Windows VMs take ~15 minutes to boot (cloud-init, WinRM setup). Linux VMs take ~5 minutes. The `rebuild-vm.sh` script handles these timeouts automatically.

### Inventory Regeneration
Always regenerate inventory after OpenTofu changes. The script reads live state, so manual edits to `inventory/production.ini` will be overwritten.

### Linting
`check.sh` runs tflint (OpenTofu) and ansible-lint. These are optional but recommended before deployment.

## Domain Details

- **Domain Name**: CDT.local
- **Domain Controller**: First Windows VM (10.10.10.21 by default)
- **Created Users**: jdoe, asmith, bwilson, mjohnson, dlee
- **Linux Admins**: jdoe, asmith (sudo access)
- **SSH Format**: `username@CDT.local@<host_ip>`
- **RDP**: Enabled on port 3389 for both Windows (native) and Linux (xrdp with LXQT)
