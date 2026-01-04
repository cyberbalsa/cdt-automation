# CDT Automation - Ansible Configuration

This directory contains all Ansible playbooks, roles, and configuration for setting up a Windows Active Directory domain with Linux members.

## Directory Structure

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
└── README.md         # This file
```

## Quick Start

### Running All Playbooks
```bash
cd ansible
ansible-playbook playbooks/site.yml
```

### Running Individual Playbooks
```bash
ansible-playbook playbooks/setup-domain-controller.yml
ansible-playbook playbooks/join-linux-domain.yml
ansible-playbook playbooks/create-domain-users.yml
```

### Testing Connectivity
```bash
ansible all -m ping
ansible windows -m ansible.windows.win_ping
ansible debian -m ping
```

## Roles

### domain_controller
Sets up the first Windows VM as an Active Directory domain controller.
- Installs AD-Domain-Services feature
- Creates new forest and domain (CDT.local)
- Configures DNS forwarders
- Creates organizational units

### linux_domain_member
Joins Linux servers to the Active Directory domain.
- Installs required packages (realmd, sssd, etc.)
- Configures Kerberos and SSSD
- Joins the domain using realm
- Configures PAM for home directory creation

### domain_users
Creates domain users and groups on the domain controller.
- Creates specified domain users
- Creates "SSH Users" and "Linux Admins" security groups
- Adds users to appropriate groups

## Configuration

### Variables

**Global variables** (`group_vars/all.yml`):
- Domain name, admin credentials
- DNS forwarders
- Organizational units
- Domain users list
- Linux admin users list

**Linux-specific variables** (`group_vars/linux_members.yml`):
- Kerberos configuration
- PAM settings
- SSSD configuration
- SSH allowed groups

**Windows-specific variables**:
- `group_vars/windows.yml` - General Windows settings
- `group_vars/windows_dc.yml` - Domain controller-specific settings

### Inventory

The inventory file (`inventory/production.ini`) is **auto-generated** by `import-tofu-to-ansible.py` and should not be edited manually. Regenerate it after any OpenTofu infrastructure changes:

```bash
cd ..
python3 import-tofu-to-ansible.py
```

## Best Practices

### Adding a New Playbook
1. Create the playbook in `playbooks/` directory
2. Add it to `playbooks/site.yml` using `import_playbook`
3. Use dynamic groups (`windows_dc`, `windows_members`, `linux_members`)

### Adding a New Role
1. Create the role structure:
   ```bash
   mkdir -p roles/my_role/{tasks,handlers,templates,files,defaults}
   ```
2. Create `tasks/main.yml` with your tasks
3. Add handlers in `handlers/main.yml` if needed
4. Define variables in `defaults/main.yml`
5. Use the role in a playbook:
   ```yaml
   - name: My Configuration
     hosts: target_group
     roles:
       - my_role
   ```

### Modifying Variables
- Edit `group_vars/all.yml` for global changes
- Edit specific group_vars files for group-specific changes
- Don't hardcode values in playbooks - use variables

## Troubleshooting

### Syntax Check
```bash
ansible-playbook playbooks/site.yml --syntax-check
```

### Dry Run (Check Mode)
```bash
ansible-playbook playbooks/site.yml --check
```

### Verbose Output
```bash
ansible-playbook playbooks/site.yml -vvv
```

### Limit to Specific Hosts
```bash
ansible-playbook playbooks/site.yml --limit cdt-win-1
```

## Common Tasks

### View Current Inventory
```bash
ansible-inventory --list
ansible-inventory --graph
```

### Check Group Membership
```bash
ansible-inventory --host cdt-win-1
```

## Notes

- All connections route through SSH jump host (`sshjump@ssh.cyberrange.rit.edu`)
- Windows VMs use WinRM over SOCKS5 proxy
- The first Windows VM is always the domain controller
- Domain name is `CDT.local`
- Default credentials are in group_vars (change for production)

For more information, see the main project documentation in `/CLAUDE.md`.
