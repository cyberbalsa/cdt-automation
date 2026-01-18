# Ansible Configuration Guide

This directory contains Ansible automation for configuring servers. This document explains how Ansible works and how to extend it for your competition.

---

## Table of Contents

1. [What This Configuration Does](#what-this-configuration-does)
2. [Directory Structure](#directory-structure)
3. [How Ansible Works](#how-ansible-works)
4. [Inventory Groups Explained](#inventory-groups-explained)
5. [Running Playbooks](#running-playbooks)
6. [Understanding the Existing Configuration](#understanding-the-existing-configuration)
7. [Adding New Services](#adding-new-services)
8. [Creating Roles](#creating-roles)
9. [Working with Variables](#working-with-variables)
10. [Debugging Problems](#debugging-problems)

---

## What This Configuration Does

This Ansible configuration sets up infrastructure across three teams:

**Blue Team (Defenders):**
- Promotes the first Windows server to an Active Directory Domain Controller
- Joins remaining Windows servers to the domain
- Joins Linux servers to the domain (using SSSD and Kerberos)
- Creates domain user accounts
- Configures remote desktop access (RDP on Windows, xRDP on Linux)

**Red Team (Attackers):**
- Configures xRDP for graphical desktop access to Kali boxes
- Kali boxes do NOT join the domain (they are attack machines)

**Grey Team (Scoring):**
- Scoring servers can be configured as needed for your competition
- The base configuration sets up xRDP for desktop access

This is a foundation. Your competition will need additional configuration for web servers, databases, mail servers, scoring systems, and other services.

---

## Directory Structure

```
ansible/
  ansible.cfg              # Ansible settings (connection options, defaults)

  inventory/
    production.ini         # Server list - auto-generated, do not edit manually

  group_vars/
    all.yml               # Variables for ALL servers
    windows.yml           # Variables for Windows servers only
    windows_dc.yml        # Variables for Domain Controller only
    linux_members.yml     # Variables for Linux servers only

  playbooks/
    site.yml              # Main playbook - runs everything in order
    setup-domain-controller.yml
    create-domain-users.yml
    join-windows-domain.yml
    join-linux-domain.yml
    activate-windows-kms.yml
    setup-rdp-windows.yml
    setup-rdp-linux.yml

  roles/
    domain_controller/    # Tasks for setting up AD Domain Controller
    linux_domain_member/  # Tasks for joining Linux to domain
    domain_users/         # Tasks for creating domain users
```

### What Each Part Does

**ansible.cfg**: Contains settings that control how Ansible connects to servers. The important settings are the SSH jump host and WinRM proxy configuration. You generally do not need to change this.

**inventory/production.ini**: Lists all servers organized by team with their IP addresses and connection details. This file is generated automatically by `import-tofu-to-ansible.py`. Do not edit it manually - your changes will be overwritten.

**group_vars/**: Contains variables organized by server group. When Ansible runs against a server, it loads variables from files matching the server's groups.

**playbooks/**: Contains the automation scripts. Each playbook performs a specific task. The `site.yml` playbook imports all others in the correct order.

**roles/**: Contains reusable automation components. Each role handles a complete configuration task (like setting up Active Directory).

---

## How Ansible Works

Ansible automates server configuration by:

1. Reading an **inventory** file to know which servers exist
2. Connecting to servers via SSH (Linux) or WinRM (Windows)
3. Running **tasks** that make configuration changes
4. Checking the result of each task before moving to the next

### Key Concepts

**Inventory**: A list of servers organized into groups. Example:
```ini
[web_servers]
web-1 ansible_host=192.168.10.10
web-2 ansible_host=192.168.10.11

[database_servers]
db-1 ansible_host=192.168.20.20
```

**Playbook**: A YAML file containing tasks to run. Example:
```yaml
---
- name: Configure Web Servers
  hosts: web_servers
  become: true
  tasks:
    - name: Install Apache
      ansible.builtin.apt:
        name: apache2
        state: present
```

**Task**: A single action performed by Ansible. Each task uses a module.

**Module**: A built-in Ansible function that performs a specific action (install package, copy file, run command, etc.).

**Role**: A collection of tasks, templates, and variables organized together for reuse.

**Variable**: A named value that can be used in playbooks. Variables let you customize behavior without changing code.

**Handler**: A special task that runs only when triggered by another task (commonly used to restart services after configuration changes).

---

## Inventory Groups Explained

The auto-generated inventory file organizes servers by team and function:

### Primary Groups (Directly Assigned)

| Group | Contents | Team |
|-------|----------|------|
| `scoring` | Scoring server(s) | Grey |
| `windows_dc` | First Blue Windows server (Domain Controller) | Blue |
| `blue_windows_members` | Blue Windows servers except DC | Blue |
| `blue_linux_members` | Blue Linux servers | Blue |
| `red_team` | Kali attack boxes | Red |

### Hierarchy Groups (Children)

These groups combine other groups for convenience:

| Group | Contains | Use Case |
|-------|----------|----------|
| `windows` | `windows_dc` + `blue_windows_members` | Target all Windows servers |
| `blue_team` | `windows_dc` + `blue_windows_members` + `blue_linux_members` | Target all Blue Team |
| `linux_members` | `blue_linux_members` + `scoring` + `red_team` | Target all Linux servers |

### Example Inventory File

```ini
# Grey Team - Scoring
[scoring]
scoring-1 ansible_host=10.10.10.11 floating_ip=100.65.4.11

# Blue Team - Windows
[windows_dc]
dc01 ansible_host=10.10.10.21 floating_ip=100.65.4.21

[blue_windows_members]
blue-win-2 ansible_host=10.10.10.22 floating_ip=100.65.4.22

# Blue Team - Linux
[blue_linux_members]
webserver ansible_host=10.10.10.31 floating_ip=100.65.4.31
blue-linux-2 ansible_host=10.10.10.32 floating_ip=100.65.4.32

# Red Team
[red_team]
red-kali-1 ansible_host=10.10.10.41 floating_ip=100.65.4.41
red-kali-2 ansible_host=10.10.10.42 floating_ip=100.65.4.42

# Hierarchy groups
[windows:children]
windows_dc
blue_windows_members

[blue_team:children]
windows_dc
blue_windows_members
blue_linux_members

[linux_members:children]
blue_linux_members
scoring
red_team
```

### Targeting Teams in Playbooks

Use the group names to run playbooks on specific teams:

```yaml
# Run on all Blue Team servers
- name: Configure Blue Team
  hosts: blue_team
  tasks:
    - name: Example task
      ansible.builtin.debug:
        msg: "This runs on Blue Team"

# Run on Red Team only
- name: Configure Red Team
  hosts: red_team
  tasks:
    - name: Example task
      ansible.builtin.debug:
        msg: "This runs on Red Team Kali boxes"

# Run on all Windows servers (DC and members)
- name: Configure Windows
  hosts: windows
  tasks:
    - name: Example task
      ansible.builtin.debug:
        msg: "This runs on all Windows servers"

# Run on Blue Linux only (not Red Team, not scoring)
- name: Configure Blue Linux
  hosts: blue_linux_members
  tasks:
    - name: Example task
      ansible.builtin.debug:
        msg: "This runs on Blue Team Linux servers"
```

---

## Running Playbooks

### From Your Local Machine

Due to network restrictions, running Ansible from your local machine can be unreliable, especially for Windows servers. The recommended approach is to run from inside the network.

### From Inside the Network (Recommended)

1. SSH to one of the Linux servers:
```bash
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<linux-floating-ip>
```

2. Install Ansible if not already installed:
```bash
sudo apt update
sudo apt install -y ansible
```

3. Copy the ansible directory to the server (if not already there):
```bash
# Run this from your local machine
scp -r -J sshjump@ssh.cyberrange.rit.edu ansible/ cyberrange@<linux-floating-ip>:~/
```

4. Run playbooks:
```bash
cd ~/ansible
ansible-playbook playbooks/site.yml
```

### Running Individual Playbooks

You do not have to run everything at once. Run individual playbooks:

```bash
# Just set up the domain controller
ansible-playbook playbooks/setup-domain-controller.yml

# Just create domain users
ansible-playbook playbooks/create-domain-users.yml

# Just set up xRDP on Linux
ansible-playbook playbooks/setup-rdp-linux.yml
```

### Common Command Options

```bash
# Run with verbose output (helpful for debugging)
ansible-playbook playbooks/site.yml -v
ansible-playbook playbooks/site.yml -vvv   # Very verbose

# Run only against specific hosts
ansible-playbook playbooks/site.yml --limit dc01

# Run only against a specific group
ansible-playbook playbooks/site.yml --limit red_team

# Check what would change without making changes
ansible-playbook playbooks/site.yml --check

# Run a single task by its tag
ansible-playbook playbooks/site.yml --tags "install_apache"
```

### Testing Connectivity

Before running playbooks, verify Ansible can reach all servers:

```bash
# Test all servers
ansible all -m ping

# Test Windows servers
ansible windows -m ansible.windows.win_ping

# Test Blue Team Linux servers
ansible blue_linux_members -m ping

# Test Red Team Kali boxes
ansible red_team -m ping
```

---

## Understanding the Existing Configuration

### The site.yml Playbook

The `site.yml` file is the master playbook. It imports other playbooks in order:

```yaml
- name: Validate inventory
  # Checks that required groups exist and have hosts

- name: Setup Domain Controller
  import_playbook: setup-domain-controller.yml
  # Runs on: windows_dc (first Blue Windows server)

- name: Join Windows Members to Domain
  import_playbook: join-windows-domain.yml
  # Runs on: blue_windows_members

- name: Activate Windows
  import_playbook: activate-windows-kms.yml
  # Runs on: windows (all Windows servers)

- name: Join Linux Members to Domain
  import_playbook: join-linux-domain.yml
  # Runs on: blue_linux_members (NOT red_team or scoring)

- name: Create Domain Users
  import_playbook: create-domain-users.yml
  # Runs on: windows_dc

- name: Setup RDP on Linux
  import_playbook: setup-rdp-linux.yml
  # Runs on: linux_members (all Linux including Red Team)

- name: Setup RDP on Windows
  import_playbook: setup-rdp-windows.yml
  # Runs on: windows (all Windows servers)
```

The order matters:
1. Domain controller must be set up first
2. Other servers join the domain after DC is ready
3. Users are created on the DC
4. RDP setup can happen anytime after servers are reachable

Note that Red Team Kali boxes only get xRDP setup - they do NOT join the domain because they are attack machines that should not have domain credentials.

### The domain_controller Role

Look at `roles/domain_controller/tasks/main.yml` to see how the domain is set up. Key tasks:

1. Install AD Domain Services feature
2. Promote the server to a domain controller
3. Configure DNS
4. Reboot and wait for services

### The linux_domain_member Role

Look at `roles/linux_domain_member/tasks/main.yml` to see how Linux servers join the domain:

1. Install required packages (realmd, sssd, krb5)
2. Configure DNS to point to the domain controller
3. Discover the domain
4. Join the domain using realm join
5. Configure SSSD for user lookups
6. Configure PAM for logins

### Group Variables

Variables are defined in `group_vars/`:

- `all.yml`: Domain name, admin credentials, domain users list
- `windows.yml`: Windows connection settings (WinRM, proxy)
- `windows_dc.yml`: Domain controller features and configuration
- `linux_members.yml`: Kerberos, SSSD, xRDP settings

---

## Adding New Services

To add a new service to your competition:

### Step 1: Decide on the Approach

For simple configurations (one or two tasks), add tasks directly to a playbook.

For complex configurations (multiple tasks, templates, handlers), create a role.

### Step 2: Create a Playbook

Create a new file in `playbooks/`:

```yaml
# playbooks/setup-webserver.yml
---
- name: Configure Web Servers
  hosts: blue_webservers
  become: true

  tasks:
    - name: Install Apache
      ansible.builtin.apt:
        name: apache2
        state: present
        update_cache: true

    - name: Start Apache
      ansible.builtin.service:
        name: apache2
        state: started
        enabled: true

    - name: Copy website files
      ansible.builtin.copy:
        src: files/website/
        dest: /var/www/html/
```

### Step 3: Add the Inventory Group

Update `import-tofu-to-ansible.py` to create the inventory group for your new server type. Then run the script to regenerate the inventory.

### Step 4: Add to site.yml

Import your new playbook in `site.yml`:

```yaml
- name: Configure Web Servers
  import_playbook: setup-webserver.yml
```

Place it in the correct position. If your service depends on another (like needing the domain to be set up), put it after that dependency.

### Step 5: Test

Run your playbook:

```bash
ansible-playbook playbooks/setup-webserver.yml -v
```

---

## Creating Roles

Roles are better than inline tasks when you have:
- Multiple related tasks
- Template files to copy
- Handlers that restart services
- Default variables that can be overridden

### Role Directory Structure

```
roles/
  myservice/
    tasks/
      main.yml        # Required: tasks to run
    handlers/
      main.yml        # Optional: handlers (restart commands)
    templates/
      config.j2       # Optional: template files
    files/
      staticfile.txt  # Optional: static files
    defaults/
      main.yml        # Optional: default variable values
```

### Example: Creating a Web Server Role

1. Create the directory structure:
```bash
mkdir -p roles/webserver/{tasks,handlers,templates,files,defaults}
```

2. Create `roles/webserver/defaults/main.yml`:
```yaml
---
web_port: 80
web_document_root: /var/www/html
```

3. Create `roles/webserver/tasks/main.yml`:
```yaml
---
- name: Install Apache
  ansible.builtin.apt:
    name: apache2
    state: present
    update_cache: true

- name: Deploy Apache configuration
  ansible.builtin.template:
    src: apache-site.conf.j2
    dest: /etc/apache2/sites-available/competition.conf
  notify: Restart Apache

- name: Enable the site
  ansible.builtin.command:
    cmd: a2ensite competition
  notify: Restart Apache

- name: Disable default site
  ansible.builtin.command:
    cmd: a2dissite 000-default
  notify: Restart Apache

- name: Ensure Apache is running
  ansible.builtin.service:
    name: apache2
    state: started
    enabled: true
```

4. Create `roles/webserver/handlers/main.yml`:
```yaml
---
- name: Restart Apache
  ansible.builtin.service:
    name: apache2
    state: restarted
```

5. Create `roles/webserver/templates/apache-site.conf.j2`:
```apache
<VirtualHost *:{{ web_port }}>
    ServerName {{ inventory_hostname }}
    DocumentRoot {{ web_document_root }}

    <Directory {{ web_document_root }}>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
```

6. Create a playbook that uses the role:
```yaml
# playbooks/setup-webserver.yml
---
- name: Configure Web Servers
  hosts: blue_webservers
  become: true
  roles:
    - webserver
```

---

## Working with Variables

### Where to Define Variables

**For all servers**: `group_vars/all.yml`

**For a specific group**: `group_vars/groupname.yml`

**In a role**: `roles/rolename/defaults/main.yml`

**In a playbook**:
```yaml
- name: Configure Servers
  hosts: all
  vars:
    my_variable: value
```

### Using Variables in Tasks

Reference variables with double curly braces:

```yaml
- name: Create user
  ansible.builtin.user:
    name: "{{ username }}"
    password: "{{ password }}"
```

### Variable Precedence

Ansible has a complex variable precedence system. In general:
1. Variables in playbooks override role defaults
2. Variables in `group_vars` override playbook variables
3. Variables passed on command line override everything

For simplicity, define variables in `group_vars` files and avoid duplicating them in multiple places.

### Lists and Loops

Define a list:
```yaml
# In group_vars/all.yml
users:
  - username: jdoe
    fullname: John Doe
    password: secret
  - username: asmith
    fullname: Alice Smith
    password: secret2
```

Use it in a task:
```yaml
- name: Create users
  ansible.builtin.user:
    name: "{{ item.username }}"
    password: "{{ item.password }}"
  loop: "{{ users }}"
```

---

## Debugging Problems

### Enable Verbose Output

Add `-v`, `-vv`, or `-vvv` for increasing verbosity:

```bash
ansible-playbook playbooks/site.yml -vvv
```

### Check Mode (Dry Run)

See what would change without making changes:

```bash
ansible-playbook playbooks/site.yml --check
```

### Run Ad-Hoc Commands

Test commands directly:

```bash
# Run a command on all servers
ansible all -m command -a "hostname"

# Check a service status on Blue Team
ansible blue_team -m command -a "systemctl status apache2"

# Get facts about a server
ansible dc01 -m setup

# Run on Red Team only
ansible red_team -m command -a "whoami"
```

### Common Errors

**"No hosts matched"**: The inventory group does not exist or is empty. Regenerate inventory with `python3 import-tofu-to-ansible.py`.

**"Connection refused" or timeout**: Server is not reachable. Check:
- Is the server running? (Look in OpenStack dashboard)
- Is the IP correct? (Check inventory file)
- Are security groups allowing the connection?
- For Windows: Wait 15-20 minutes after creation for WinRM to be ready

**"Authentication failed"**: Wrong username or password. Check:
- Inventory file has correct credentials
- `group_vars` files have correct passwords
- For domain users, domain must be set up first

**"Permission denied"**: The task needs elevated privileges. Add `become: true` to the play or task.

**Task fails but no clear error**: Add `-vvv` for verbose output. Look for error messages in the output.

### Checking Server State

SSH to the server and check manually:

```bash
# Check if a service is running
systemctl status apache2

# Check if a package is installed
dpkg -l | grep apache2

# Check if a file exists
ls -la /etc/apache2/sites-available/

# Check logs
journalctl -u apache2 -n 50
```

---

## Default Credentials

| Account Type | Username | Password |
|--------------|----------|----------|
| Linux local account | cyberrange | Cyberrange123! |
| Windows local account | cyberrange | Cyberrange123! |
| Domain Administrator | Administrator | Cyberrange123! |
| Domain users (jdoe, asmith, etc.) | (username) | UserPass123! |

Note: Red Team Kali boxes use only the local `cyberrange` account since they do not join the domain.

---

## Useful Ansible Modules

### For Linux Servers

| Module | Purpose | Example |
|--------|---------|---------|
| `apt` | Install packages | `apt: name=nginx state=present` |
| `service` | Manage services | `service: name=nginx state=started` |
| `copy` | Copy files | `copy: src=file.txt dest=/path/file.txt` |
| `template` | Copy templates with variables | `template: src=config.j2 dest=/etc/config` |
| `file` | Create/modify files and directories | `file: path=/dir state=directory` |
| `user` | Create users | `user: name=john password=...` |
| `command` | Run commands | `command: cmd="whoami"` |
| `lineinfile` | Edit lines in files | `lineinfile: path=/etc/file line="text"` |

### For Windows Servers

| Module | Purpose | Example |
|--------|---------|---------|
| `win_feature` | Install Windows features | `win_feature: name=Web-Server state=present` |
| `win_service` | Manage services | `win_service: name=W3SVC state=started` |
| `win_copy` | Copy files | `win_copy: src=file.txt dest=C:\file.txt` |
| `win_template` | Copy templates | `win_template: src=config.j2 dest=C:\config.txt` |
| `win_user` | Create users | `win_user: name=john password=...` |
| `win_command` | Run commands | `win_command: whoami` |
| `win_powershell` | Run PowerShell | `win_powershell: script="Get-Service"` |

See the Ansible documentation for complete module references:
- Linux: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/
- Windows: https://docs.ansible.com/ansible/latest/collections/ansible/windows/

---

## Next Steps

1. Read through the existing playbooks to understand the patterns used
2. Identify what additional services your competition needs
3. Create roles for each service type
4. Create playbooks that use those roles
5. Add the playbooks to site.yml
6. Test each playbook individually before running everything together
