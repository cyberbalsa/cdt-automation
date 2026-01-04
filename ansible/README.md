# CDT Automation - Ansible Configuration

> **For Students**: This directory contains all the Ansible automation for deploying an Active Directory attack/defend lab environment.

## 🎯 What Does This Do?

This Ansible configuration automatically builds a complete Windows Active Directory domain with both Windows and Linux member machines. It's designed for cybersecurity students to practice:

- **Red Team**: Offensive security techniques (Kerberoasting, pass-the-hash, lateral movement)
- **Blue Team**: Defensive monitoring and incident response
- **Mixed Environment**: Realistic corporate network with Windows + Linux integration

## 📁 Directory Structure

```
ansible/
├── playbooks/              # Automation playbooks (what to do)
│   ├── site.yml           # Main playbook - runs everything
│   ├── setup-domain-controller.yml
│   ├── create-domain-users.yml
│   ├── join-windows-domain.yml
│   ├── join-linux-domain.yml
│   ├── setup-rdp-windows.yml
│   └── setup-rdp-linux.yml
├── roles/                  # Reusable automation components
│   ├── domain_controller/ # AD DC setup
│   ├── linux_domain_member/ # Linux AD integration
│   └── domain_users/      # User/group creation
├── group_vars/            # Configuration variables
│   ├── all.yml           # Global settings (domain name, users)
│   ├── windows.yml       # Windows-specific settings
│   ├── windows_dc.yml    # Domain controller settings
│   └── linux_members.yml # Linux-specific settings
├── inventory/             # List of servers
│   └── production.ini    # Auto-generated from OpenTofu
├── ansible.cfg           # Ansible configuration
└── README.md            # This file
```

## 🚀 Quick Start

### Prerequisites

1. **OpenTofu infrastructure deployed**:
   ```bash
   cd opentofu
   source ../app-cred-openrc.sh
   tofu apply
   cd ..
   ```

2. **Generate Ansible inventory**:
   ```bash
   python3 import-tofu-to-ansible.py
   ```

3. **Verify connectivity**:
   ```bash
   cd ansible
   ansible all -m ping
   ```

### Full Deployment

Deploy everything in one command:

```bash
cd ansible
ansible-playbook playbooks/site.yml
```

**Expected runtime**: 30-45 minutes (includes multiple VM reboots)

### Individual Playbooks

Run specific steps:

```bash
# Just setup domain controller
ansible-playbook playbooks/setup-domain-controller.yml

# Just create users
ansible-playbook playbooks/create-domain-users.yml

# Just join Windows to domain
ansible-playbook playbooks/join-windows-domain.yml

# Just join Linux to domain
ansible-playbook playbooks/join-linux-domain.yml

# Just setup RDP
ansible-playbook playbooks/setup-rdp-windows.yml
ansible-playbook playbooks/setup-rdp-linux.yml
```

## 🔐 Default Credentials

### Domain Administrator
- **Username**: `Administrator` or `CDT\Administrator`
- **Password**: `Cyberrange123!`

### Domain Users (created by playbook)
All domain users have password: `UserPass123!`

| Username | Full Name | Groups | Notes |
|----------|-----------|--------|-------|
| jdoe | John Doe | Domain Users, IT Staff | Has sudo on Linux |
| asmith | Alice Smith | Domain Users, IT Staff, **Domain Admins** | **HIGH VALUE TARGET** |
| bwilson | Bob Wilson | Domain Users | Regular user |
| mjohnson | Mary Johnson | Domain Users, Accounting | Regular user |
| dlee | David Lee | Domain Users, Engineering | Regular user |

### VM Local Accounts
- **Linux**: `cyberrange:Cyberrange123!`
- **Windows**: `cyberrange:Cyberrange123!`

## 🎮 Using Your Lab

### RDP Access

**Windows Machines**:
```bash
# From Windows
mstsc /v:<ip_address>:3389

# From Linux/Mac
xfreerdp /v:<ip_address> /u:CDT\\jdoe /p:UserPass123!
```

**Linux Machines (xRDP)**:
```bash
# Same as Windows, but select "Xorg" session at login
xfreerdp /v:<ip_address> /u:jdoe /p:UserPass123!
```

### SSH Access (Linux Only)

```bash
# Domain user SSH
ssh jdoe@<linux_ip>

# Alternative format
ssh jdoe@CDT.local@<linux_ip>
```

### Finding IP Addresses

```bash
# View inventory
cat inventory/production.ini

# Get specific host IPs
ansible windows_dc --list-hosts
ansible linux_members -m debug -a "var=ansible_host"
```

## 🛠️ Customizing Your Lab

### Adding More Users

Edit `group_vars/all.yml`:

```yaml
domain_users:
  - username: tstark
    firstname: Tony
    surname: Stark
    password: IAmIronMan123!
    groups:
      - Domain Users
      - Engineering
```

Then re-run:
```bash
ansible-playbook playbooks/create-domain-users.yml
```

### Changing Domain Name

Edit `group_vars/all.yml`:
```yaml
domain_name: MYCOMPANY.local
domain_netbios_name: MYCOMPANY
```

Then **rebuild everything** (domain name can't be changed after deployment).

### Creating Attack Scenarios

**Example: Intentional Vulnerabilities**

Edit `group_vars/windows_dc.yml`:
```yaml
enable_smbv1: true        # Vulnerable to EternalBlue
enable_llmnr: true        # Vulnerable to Responder attacks
weak_password_policy: true # Easy password cracking
```

### Adding Services

Create a new playbook in `playbooks/`:

```yaml
---
- name: Install Web Server
  hosts: linux_members
  become: true
  tasks:
    - name: Install Apache
      ansible.builtin.apt:
        name: apache2
        state: present
```

Run it:
```bash
ansible-playbook playbooks/install-webserver.yml
```

## 🔧 Troubleshooting

### "No hosts matched" error

**Problem**: Inventory not generated or out of date

**Solution**:
```bash
python3 import-tofu-to-ansible.py
```

### Playbook fails with connection timeout

**Problem**: Jump host authentication or VM not ready

**Solutions**:
1. Verify SSH jump host works: `ssh sshjump@ssh.cyberrange.rit.edu`
2. Check VMs are running: `cd opentofu && tofu show`
3. Wait for VMs to finish booting (Windows takes 15 minutes)

### Domain join fails

**Problem**: DC not fully ready or DNS issues

**Solutions**:
1. Verify DC is running: `ansible windows_dc -m ansible.windows.win_ping`
2. Wait 5-10 minutes after DC promotion
3. Check DNS settings on members point to DC
4. Re-run: `ansible-playbook playbooks/join-windows-domain.yml`

### Linux domain join fails

**Problem**: Time sync, DNS, or package issues

**Solutions**:
```bash
# SSH into Linux machine
ssh cyberrange@<linux_ip>

# Check time (must be within 5 minutes of DC)
date

# Check DNS
nslookup CDT.local

# Check Kerberos
kinit Administrator@CDT.LOCAL
klist

# Manual join for debugging
sudo realm join -U Administrator CDT.local -v
```

### xRDP black screen

**Problem**: Desktop environment not loading

**Solutions**:
1. At login, select **"Xorg"** session (not "Default")
2. Check logs: `ssh into machine && sudo tail -f /var/log/xrdp.log`
3. Verify XFCE installed: `dpkg -l | grep xfce`

## 📚 Learning Resources

### Understanding the Code

Every playbook and role is **heavily commented** with explanations for students. Read through:

- `playbooks/setup-domain-controller.yml` - Learn AD deployment
- `roles/domain_controller/tasks/main.yml` - See PowerShell automation
- `roles/linux_domain_member/tasks/main.yml` - Learn Linux AD integration
- `group_vars/*.yml` - Understand configuration management

### Attack Techniques Covered

Each playbook includes comments on:
- What vulnerabilities are being created
- Which attack techniques apply
- Defensive measures to try
- Tools to use (BloodHound, mimikatz, CrackMapExec, etc.)

### Best Practices for Students

1. **Read the playbooks** - They're teaching tools, not just automation
2. **Experiment** - Break things, rebuild, learn from failures
3. **Document** - Keep notes on what works and what doesn't
4. **Practice both sides** - Try attacks, then implement defenses
5. **Use version control** - Commit your changes to learn Git

## 🎓 Attack/Defend Scenarios

### Red Team Scenarios

1. **Initial Access**
   - Password spraying against domain users
   - Phishing simulation (manual)

2. **Credential Dumping**
   - mimikatz on Windows machines
   - Extract Kerberos tickets from Linux

3. **Lateral Movement**
   - Pass-the-hash attacks
   - WinRM/RDP with stolen credentials

4. **Privilege Escalation**
   - Exploit weak sudo config on Linux
   - Kerberoasting service accounts

5. **Domain Dominance**
   - DCSync attack against domain controller
   - Golden ticket creation

### Blue Team Scenarios

1. **Monitoring**
   - Enable Windows Event Logging
   - Set up syslog on Linux
   - Monitor failed logins

2. **Hardening**
   - Disable SMBv1
   - Implement account lockout policies
   - Enable NLA for RDP

3. **Incident Response**
   - Detect mimikatz usage
   - Identify lateral movement
   - Find persistence mechanisms

4. **Forensics**
   - Analyze Windows Event Logs
   - Review /var/log on Linux
   - Track attacker timeline

## 🔄 Rebuilding Individual VMs

If a VM gets corrupted or you want to start fresh:

```bash
# From project root
./rebuild-vm.sh <vm_ip>

# Example
./rebuild-vm.sh 10.10.10.21  # Rebuild DC
./rebuild-vm.sh 10.10.10.31  # Rebuild first Linux VM
```

This script:
1. Taints the VM in OpenTofu
2. Rebuilds just that VM
3. Regenerates inventory
4. Re-runs Ansible on that VM

## 📊 Checking Your Work

### Verify Domain Controller

```bash
ansible-playbook playbooks/setup-domain-controller.yml --check
```

### List All Domain Users

```bash
ansible windows_dc -m ansible.windows.win_powershell -a "script='Get-ADUser -Filter * | Select-Object Name,SamAccountName'"
```

### Test Domain User Login

```bash
# Windows
ansible windows -m ansible.windows.win_powershell -a "script='whoami'"

# Linux (after domain join)
ansible linux_members -m shell -a "getent passwd jdoe"
```

## 🏆 Advanced: Creating Custom Roles

Students can create their own roles for reusable tasks:

```bash
mkdir -p roles/my_custom_role/{tasks,defaults,handlers,templates}
```

Example use cases:
- Install vulnerable web applications
- Deploy honeypot services
- Configure custom logging
- Set up attacker tools (in isolated environment!)

## 📖 Additional Documentation

- **Project README**: `../CLAUDE.md` (overall project documentation)
- **OpenTofu Config**: `../opentofu/` (infrastructure as code)
- **Linting**: Run `../check.sh` before committing changes

## ⚠️ Security Warning

This lab creates **intentionally vulnerable** systems for educational purposes:

- ❌ Weak passwords
- ❌ Disabled security features
- ❌ Known vulnerabilities enabled
- ❌ No network segmentation

**NEVER** deploy this in production or on public networks!

**ALWAYS** use in isolated lab environments only!

## 🤝 Contributing

Students: Found a bug or want to add a feature?

1. Create a new branch
2. Make your changes
3. Run `../check.sh` to lint
4. Commit with descriptive messages
5. Share with your instructor

## 📝 License

Educational use only - Check with your institution for usage policies.

---

**Questions?** Check the comments in the playbooks or ask your instructor!

**Happy Hacking!** (Responsibly) 🎓🔒
