# CDT Domain Setup with Ansible

This Ansible project sets up a complete Active Directory domain called "CDT" with Windows and Linux servers.

## Infrastructure Overview

- **Domain Controller**: First Windows host (automatically assigned)
- **Windows Members**: All additional Windows hosts
- **Linux Members**: All Debian hosts
- **Domain**: CDT.local

The infrastructure is **fully dynamic** - the first Windows host in the inventory is automatically designated as the domain controller, and you can add unlimited Windows or Linux members.

## Prerequisites

1. All Windows servers should have WinRM enabled
2. All Linux servers should have SSH access as root
3. Update passwords in `inventory.ini` if different from defaults

## Usage

### Run Complete Setup
```bash
ansible-playbook -i inventory.ini site.yml
```

### Run Individual Components
```bash
# Setup domain controller only
ansible-playbook -i inventory.ini setup-domain-controller.yml

# Join Windows servers to domain
ansible-playbook -i inventory.ini join-windows-domain.yml

# Join Linux servers to domain  
ansible-playbook -i inventory.ini join-linux-domain.yml

# Create users and configure SSH
ansible-playbook -i inventory.ini create-domain-users.yml
```

## Created Users

The following domain users are created with password `UserPass123!`:
- `jdoe` (John Doe) - Linux Admin
- `asmith` (Alice Smith) - Linux Admin  
- `bwilson` (Bob Wilson)
- `mjohnson` (Mary Johnson)
- `dlee` (David Lee)

## SSH Access

Users can SSH to Linux boxes using their domain credentials:
```bash
ssh jdoe@CDT.local@10.10.10.31
# Password: UserPass123!
```

Linux Admins (jdoe, asmith) have sudo access without password.

## Security Groups

- **SSH Users**: All created users, allows SSH access to Linux boxes
- **Linux Admins**: jdoe and asmith, provides sudo access

## Configuration Notes

- Password authentication is enabled for SSH
- Home directories are created automatically on first login
- SSSD is configured for AD authentication on Linux boxes
- DNS is configured to use the domain controller

## Troubleshooting

### Check domain join status on Linux:
```bash
realm list
id jdoe@CDT.local
```

### Check SSH configuration:
```bash
sshd -t
systemctl status sssd
```

### Check Windows domain membership:
```powershell
Get-ComputerInfo | Select-Object WindowsDomainName
```

---

# Customizing Your Infrastructure

This section explains how to create your own network of machines and extend the project with custom playbooks.

## How the Infrastructure Works

The project uses **OpenTofu** (Terraform) to provision VMs on OpenStack, then automatically generates an Ansible inventory from the provisioned infrastructure.

### Workflow:
1. OpenTofu creates VMs based on `variables.tf` configuration
2. The `import-tofu-to-ansible.py` script reads OpenTofu outputs
3. Script generates `inventory.ini` with dynamic groups
4. Ansible playbooks use the inventory to configure the VMs

## Adding or Removing Machines

### Option 1: Edit Variables File (Recommended)

Edit `../opentofu/variables.tf` and modify the counts:

```hcl
variable "windows_count" { default = 5 }  # Change from 3 to 5
variable "debian_count" { default = 6 }   # Change from 4 to 6
```

Then apply the changes:

```bash
cd ../opentofu
tofu apply
cd ../ansible
python3 ../import-tofu-to-ansible.py
```

### Option 2: Use Command Line Overrides

You can override variables without editing files:

```bash
cd ../opentofu
tofu apply -var="windows_count=5" -var="debian_count=6"
cd ../ansible
python3 ../import-tofu-to-ansible.py
```

### Understanding the Inventory Groups

The auto-generated `inventory.ini` creates these groups:

- **`[windows]`** - All Windows VMs (first one becomes DC)
- **`[debian]`** - All Debian/Linux VMs
- **`[windows_dc]`** - First Windows VM (domain controller)
- **`[windows_members]`** - Windows VMs 2-N (domain members)
- **`[linux_members]`** - All Debian VMs (domain members)
- **`[all_vms:children]`** - All VMs combined

## Customizing the Network

### Change IP Addressing

Edit `../opentofu/variables.tf`:

```hcl
variable "subnet_cidr" { default = "10.20.30.0/24" }  # Change network
```

Then update `../opentofu/instances.tf` to match your IP scheme:

```hcl
# Windows VMs
network {
  uuid = openstack_networking_network_v2.cdt_net.id
  fixed_ip_v4 = "10.20.30.2${count.index + 1}"  # 10.20.30.21, .22, .23
}

# Debian VMs
network {
  uuid = openstack_networking_network_v2.cdt_net.id
  fixed_ip_v4 = "10.20.30.3${count.index + 1}"  # 10.20.30.31, .32, .33, .34
}
```

### Change VM Sizes or Images

Edit `../opentofu/variables.tf`:

```hcl
variable "flavor_name" { default = "large" }  # Change from "medium"
variable "windows_image_name" { default = "WindowsServer2025" }
variable "debian_image_name" { default = "Debian12" }
```

## Creating Custom Playbooks

### Example: Install a Web Server on Linux

Create `install-webserver.yml`:

```yaml
---
- name: Install Apache Web Server
  hosts: linux_members
  become: true
  tasks:
    - name: Install Apache
      ansible.builtin.apt:
        name: apache2
        state: present
        update_cache: true

    - name: Start Apache service
      ansible.builtin.systemd:
        name: apache2
        state: started
        enabled: true

    - name: Create custom index page
      ansible.builtin.copy:
        content: |
          <h1>Hello from {{ inventory_hostname }}</h1>
          <p>Internal IP: {{ internal_ip }}</p>
        dest: /var/www/html/index.html
        mode: '0644'
```

Run it standalone:

```bash
ansible-playbook -i inventory.ini install-webserver.yml
```

**Or import it into `site.yml` to run as part of the main setup:**

Edit `site.yml` and add the import after the existing playbooks:

```yaml
- name: Install Web Server
  import_playbook: install-webserver.yml
```

This allows you to run all playbooks together with `ansible-playbook -i inventory.ini site.yml`

### Example: Configure Windows Features

Create `install-iis.yml`:

```yaml
---
- name: Install IIS on Windows Members
  hosts: windows_members
  gather_facts: false
  tasks:
    - name: Install IIS
      ansible.windows.win_feature:
        name: Web-Server
        state: present
        include_management_tools: true

    - name: Create custom default page
      ansible.windows.win_copy:
        content: |
          <h1>{{ inventory_hostname }}</h1>
          <p>Internal IP: {{ internal_ip }}</p>
        dest: C:\inetpub\wwwroot\index.html
```

To include this in your main setup, add to `site.yml`:

```yaml
- name: Install IIS on Windows
  import_playbook: install-iis.yml
```

### Example: Target Specific Hosts

Create `backup-dc.yml`:

```yaml
---
- name: Backup Domain Controller
  hosts: windows_dc  # Only runs on the first Windows host
  gather_facts: false
  tasks:
    - name: Create backup directory
      ansible.windows.win_file:
        path: C:\Backups
        state: directory

    - name: Backup Active Directory
      ansible.windows.win_shell: |
        wbadmin start systemstatebackup -backupTarget:C:\Backups -quiet
```

## Advanced Customization Examples

### Adding a New Group of VMs

1. **Edit `../opentofu/instances.tf`** - Add new VM resources:

```hcl
resource "openstack_compute_instance_v2" "database" {
  count       = 2
  name        = "cdt-db-${count.index + 1}"
  image_name  = var.debian_image_name
  flavor_name = "large"
  key_pair    = var.keypair

  network {
    uuid = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.4${count.index + 1}"
  }
}
```

2. **Edit `../opentofu/outputs.tf`** - Export the new VMs:

```hcl
output "database_vm_names" {
  value = [for vm in openstack_compute_instance_v2.database : vm.name]
}

output "database_vm_ips" {
  value = [for fip in openstack_networking_floatingip_v2.db_fip : fip.address]
}

output "database_vm_internal_ips" {
  value = [for vm in openstack_compute_instance_v2.database : vm.access_ip_v4]
}
```

3. **Update `../import-tofu-to-ansible.py`** - Add handling for new group:

```python
# In create_inventory function, add:
f.write("\n[database]\n")
db_names = tofu_data.get('database_vm_names', {}).get('value', [])
db_ips = tofu_data.get('database_vm_ips', {}).get('value', [])
db_internal_ips = tofu_data.get('database_vm_internal_ips', {}).get('value', [])

for name, ip, internal_ip in zip(db_names, db_ips, db_internal_ips):
    f.write(f"{name} ansible_host={ip} internal_ip={internal_ip}\n")
```

4. **Create playbook** - `setup-databases.yml`:

```yaml
---
- name: Setup Database Servers
  hosts: database
  become: true
  tasks:
    - name: Install PostgreSQL
      ansible.builtin.apt:
        name:
          - postgresql
          - postgresql-contrib
        state: present
```

### Using Dynamic Variables

All playbooks have access to these variables for each host:

- `{{ inventory_hostname }}` - Host name (e.g., cdt-win-1)
- `{{ ansible_host }}` - External/floating IP
- `{{ internal_ip }}` - Internal network IP
- `{{ hostvars[groups['windows'][0]]['internal_ip'] }}` - DC internal IP
- `{{ groups['linux_members'] }}` - List of all Linux member hostnames
- `{{ domain_name }}` - Set in your playbook vars (default: CDT)

### Example: Dynamic Configuration

```yaml
---
- name: Configure monitoring
  hosts: all_vms
  vars:
    monitoring_server: "{{ hostvars[groups['linux_members'][0]]['internal_ip'] }}"
  tasks:
    - name: Display monitoring config
      ansible.builtin.debug:
        msg: "This host ({{ inventory_hostname }}) will report to {{ monitoring_server }}"
```

## Best Practices

1. **Always regenerate inventory after OpenTofu changes:**
   ```bash
   cd ../opentofu && tofu apply
   cd ../ansible && python3 ../import-tofu-to-ansible.py
   ```

2. **Test playbooks on a subset first:**
   ```bash
   ansible-playbook -i inventory.ini --limit cdt-debian-1 your-playbook.yml
   ```

3. **Use check mode to preview changes:**
   ```bash
   ansible-playbook -i inventory.ini --check your-playbook.yml
   ```

4. **Keep your playbooks idempotent** - They should be safe to run multiple times

5. **Use dynamic groups** instead of hardcoding hostnames - This makes your playbooks scalable

6. **Import new playbooks into `site.yml`** - When creating custom playbooks, add them to `site.yml` using `import_playbook` so they run as part of the main setup workflow

## Rebuilding Individual VMs

The `rebuild-vm.sh` script allows you to rebuild a specific VM and automatically reconfigure it.

### Usage

```bash
cd ..
./rebuild-vm.sh <internal_ip or floating_ip>
```

### Examples

```bash
# Rebuild using internal IP
./rebuild-vm.sh 10.10.10.21

# Rebuild using floating IP
./rebuild-vm.sh 100.65.4.55
```

### What the Script Does

1. **Finds the VM** by searching for the provided IP (internal or floating)
2. **Confirms rebuild** - asks for your confirmation
3. **Taints the resource** - marks it for rebuild in OpenTofu
4. **Rebuilds the VM** - destroys and recreates only that specific VM
5. **Regenerates inventory** - updates `inventory.ini` with new details
6. **Waits for VM to boot** - uses appropriate timeout:
   - Windows: 15 minutes (they take longer)
   - Linux: 5 minutes
7. **Tests connectivity** - uses `win_ping` for Windows, `ping` for Linux
8. **Runs playbooks** - automatically runs the correct configuration:
   - **Domain Controller** (first Windows): `setup-domain-controller.yml`
   - **Windows Members**: `join-windows-domain.yml`
   - **Linux Members**: `join-linux-domain.yml` + `create-domain-users.yml`

### Use Cases

- **VM is corrupted** - Rebuild and reconfigure automatically
- **Testing changes** - Quickly rebuild a VM to test new configurations
- **Domain issues** - Rebuild the DC if it has problems
- **Clean slate** - Reset a specific VM without affecting others

### Example Output

```bash
$ ./rebuild-vm.sh 10.10.10.21
[INFO] Target IP: 10.10.10.21
[INFO] Fetching OpenTofu state...
[INFO] Searching for VM with IP: 10.10.10.21...
[SUCCESS] Found VM: cdt-win-1 (type: windows, index: 0)
[WARNING] About to rebuild: cdt-win-1
[WARNING] Resource: openstack_compute_instance_v2.windows[0]

Are you sure you want to rebuild this VM? (yes/no): yes
[INFO] Tainting resources for rebuild...
[INFO] Rebuilding VM with OpenTofu...
[INFO] Waiting for VM to come online...
[INFO] Detected Windows VM - using extended timeout (15 minutes)
[SUCCESS] VM is online and reachable!
[INFO] VM is the Domain Controller - will run DC setup
[INFO] Running playbook: setup-domain-controller.yml
[SUCCESS] Playbook setup-domain-controller.yml completed successfully
[SUCCESS] ==============================================
[SUCCESS] VM Rebuild and Configuration Complete!
[SUCCESS] ==============================================
```

## Quick Reference

### Common OpenTofu Commands

```bash
cd ../opentofu
tofu init          # Initialize (first time only)
tofu plan          # Preview changes
tofu apply         # Apply changes
tofu destroy       # Destroy all infrastructure
tofu output -json  # View outputs (used by Python script)
```

### Regenerate Inventory

```bash
python3 ../import-tofu-to-ansible.py
```

Or with custom paths:

```bash
python3 ../import-tofu-to-ansible.py opentofu ansible inventory.ini
```

### Testing Connectivity

```bash
ansible all -i inventory.ini -m ping
ansible windows -i inventory.ini -m win_ping
ansible debian -i inventory.ini -m ping
```

## Learning Resources

- **Ansible Documentation**: https://docs.ansible.com/
- **OpenTofu Documentation**: https://opentofu.org/docs/
- **Ansible Windows Modules**: https://docs.ansible.com/ansible/latest/collections/ansible/windows/
- **Jinja2 Templates**: https://jinja.palletsprojects.com/ (used in playbooks)