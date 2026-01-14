# Ansible Configuration Guide

This directory contains Ansible automation for configuring servers. This document explains how Ansible works and how to extend it for your competition.

---

## Table of Contents

1. [What This Configuration Does](#what-this-configuration-does)
2. [Directory Structure](#directory-structure)
3. [How Ansible Works](#how-ansible-works)
4. [Running Playbooks](#running-playbooks)
5. [Understanding the Existing Configuration](#understanding-the-existing-configuration)
6. [Adding New Services](#adding-new-services)
7. [Creating Roles](#creating-roles)
8. [Working with Variables](#working-with-variables)
9. [Debugging Problems](#debugging-problems)

---

## What This Configuration Does

This Ansible configuration sets up a Windows Active Directory domain environment:

1. Promotes the first Windows server to a Domain Controller
2. Joins remaining Windows servers to the domain
3. Joins Linux servers to the domain (using SSSD and Kerberos)
4. Creates domain user accounts
5. Configures remote desktop access on all servers

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
    setup-rdp-windows.yml
    setup-rdp-linux.yml

  roles/
    domain_controller/    # Tasks for setting up AD Domain Controller
    linux_domain_member/  # Tasks for joining Linux to domain
    domain_users/         # Tasks for creating domain users
```

### What Each Part Does

**ansible.cfg**: Contains settings that control how Ansible connects to servers. The important settings are the SSH jump host and WinRM proxy configuration. You generally do not need to change this.

**inventory/production.ini**: Lists all servers with their IP addresses and connection details. This file is generated automatically by `import-tofu-to-ansible.py`. Do not edit it manually - your changes will be overwritten.

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

## Running Playbooks

### From Your Local Machine

Due to network restrictions, running Ansible from your local machine can be unreliable, especially for Windows servers. The recommended approach is to run from inside the network.

### From Inside the Network (Recommended)

1. SSH to one of the Linux servers (typically the fourth one):
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
```

### Common Command Options

```bash
# Run with verbose output (helpful for debugging)
ansible-playbook playbooks/site.yml -v
ansible-playbook playbooks/site.yml -vvv   # Very verbose

# Run only against specific hosts
ansible-playbook playbooks/site.yml --limit web-1

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

# Test Linux servers
ansible linux_members -m ping
```

---

## Understanding the Existing Configuration

### The site.yml Playbook

The `site.yml` file is the master playbook. It imports other playbooks in order:

```yaml
- name: Validate inventory
  # Checks that required groups exist

- name: Setup Domain Controller
  import_playbook: setup-domain-controller.yml

- name: Create Domain Users
  import_playbook: create-domain-users.yml

- name: Join Windows Members to Domain
  import_playbook: join-windows-domain.yml

- name: Join Linux Members to Domain
  import_playbook: join-linux-domain.yml

- name: Setup RDP on Windows
  import_playbook: setup-rdp-windows.yml

- name: Setup xRDP on Linux
  import_playbook: setup-rdp-linux.yml
```

The order matters. The domain controller must be set up before users can be created, and users must exist before other servers join the domain.

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
- `windows_dc.yml`: Domain controller features and attack surface settings
- `linux_members.yml`: Kerberos, SSSD, and xRDP settings

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
  hosts: web_servers
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
  hosts: web_servers
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

# Check a service status
ansible web_servers -m command -a "systemctl status apache2"

# Get facts about a server
ansible web-1 -m setup
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
