# CDT Automation - Competition Infrastructure Template

This project provides a starting point for Grey Teams building attack/defend cybersecurity competition infrastructure. It demonstrates how to use OpenTofu (Terraform) for creating cloud resources and Ansible for configuring servers.

Use this as a foundation. You will need to modify and extend it significantly to meet your competition's requirements.

---

## Table of Contents

1. [What This Template Provides](#what-this-template-provides)
2. [Understanding the Tools](#understanding-the-tools)
3. [Setting Up Your Environment](#setting-up-your-environment)
4. [Using This Template](#using-this-template)
5. [Customizing for Your Competition](#customizing-for-your-competition)
6. [OpenTofu Basics](#opentofu-basics)
7. [Ansible Basics](#ansible-basics)
8. [Common Operations](#common-operations)
9. [Troubleshooting](#troubleshooting)

---

## What This Template Provides

This template creates a basic Active Directory domain environment:

- One Windows Domain Controller
- Two Windows member servers
- Four Linux member servers joined to the domain
- A private network connecting all servers
- Floating IPs for external access

This is NOT a complete competition environment. It is a starting point that demonstrates the patterns you will use to build your own infrastructure. Your competition will likely need:

- More network segments (DMZ, internal, management, Red Team network)
- Additional services (web servers, mail servers, databases, etc.)
- Team workstations (one per Blue Team member, one per Red Team member)
- A scoring engine
- Custom vulnerabilities and flags
- Firewall/router between network segments

---

## Understanding the Tools

### What is OpenTofu?

OpenTofu is a tool that creates cloud infrastructure by reading configuration files. Instead of clicking through the OpenStack web interface to create a server, you write a file that describes what you want:

```hcl
resource "openstack_compute_instance_v2" "web_server" {
  name        = "competition-web-01"
  image_name  = "debian-trixie-amd64-cloud"
  flavor_name = "medium"
}
```

When you run `tofu apply`, OpenTofu creates the server for you. Benefits:

- Your infrastructure is documented in code
- You can recreate everything from scratch by running one command
- Changes are tracked in version control
- You can share your infrastructure definition with teammates

OpenTofu is a fork of Terraform. The commands and syntax are identical. Documentation for either tool applies to both.

### What is Ansible?

Ansible configures servers after they exist. Instead of logging into each server and running commands manually, you write a playbook that describes the desired state:

```yaml
- name: Install and configure Apache
  hosts: web_servers
  tasks:
    - name: Install Apache package
      ansible.builtin.apt:
        name: apache2
        state: present

    - name: Start Apache service
      ansible.builtin.service:
        name: apache2
        state: started
        enabled: true
```

When you run `ansible-playbook`, Ansible connects to all servers in the group and runs the tasks. Benefits:

- Configure many servers identically with one command
- Configuration is documented and repeatable
- Changes can be tested and reviewed before applying
- Playbooks can be run multiple times safely (idempotent)

### How They Work Together

1. You write OpenTofu configuration files describing your infrastructure
2. You run `tofu apply` to create the servers, networks, and other resources
3. A Python script reads OpenTofu's output and generates an Ansible inventory file
4. Ansible reads the inventory to know which servers exist and how to connect
5. You run Ansible playbooks to configure the servers

This separation means you can destroy and recreate servers without losing your configuration logic, and you can update configurations without recreating servers.

---

## Setting Up Your Environment

### Required Software

Install these tools on your local machine:

**Git** - for version control
```bash
# Check if installed
git --version

# Install on Ubuntu/Debian
sudo apt update && sudo apt install git

# Install on macOS
brew install git
```

**OpenTofu** - for creating infrastructure
```bash
# Follow instructions at https://opentofu.org/docs/intro/install/

# Verify installation
tofu version
```

**Ansible** - for configuring servers
```bash
# Install on Ubuntu/Debian
sudo apt update && sudo apt install ansible

# Install on macOS
brew install ansible

# Verify installation
ansible --version
```

**Python 3** - for running helper scripts
```bash
# Usually pre-installed, verify with
python3 --version
```

### SSH Key Setup

You need an RSA SSH key pair. Windows servers require RSA format.

```bash
# Check if you have one
ls ~/.ssh/id_rsa*

# Create one if needed
ssh-keygen -t rsa -b 4096
```

Upload your public key to OpenStack:

1. Go to https://openstack.cyberrange.rit.edu
2. Navigate to Compute then Key Pairs
3. Click Import Public Key
4. Name it something memorable (you will need this name later)
5. Paste the contents of `~/.ssh/id_rsa.pub`

### OpenStack Credentials

OpenTofu authenticates to OpenStack using **environment variables**. You download a credentials file from OpenStack and source it before running commands.

**Setup Process:**

1. Go to https://openstack.cyberrange.rit.edu
2. Navigate to Identity then Application Credentials
3. Click Create Application Credential
4. Give it a name like `grey-team-automation`
5. Click Create Application Credential
6. Click Download openrc file (save the secret - it is only shown once)
7. Move the downloaded file to this project directory

Run the setup script to configure credentials:

```bash
./quick-start.sh
```

The script will find your credentials file and rename it to `app-cred-openrc.sh`.

**How it works:**

The downloaded openrc file is a shell script that sets environment variables (`OS_APPLICATION_CREDENTIAL_ID`, `OS_APPLICATION_CREDENTIAL_SECRET`, etc.). When you run `source app-cred-openrc.sh`, these variables are loaded into your shell session. The OpenStack provider in `main.tf` automatically reads these environment variables.

You must source the credentials file in every new terminal session before running `tofu` commands.

### Configure Your SSH Key Name

Edit `opentofu/variables.tf` and find the `keypair_name` variable. Change it to match the name you used when uploading your key to OpenStack.

---

## Using This Template

### First Time Setup

```bash
# 1. Clone this repository
git clone <your-repo-url>
cd cdt-automation

# 2. Run the setup script
./quick-start.sh

# 3. Edit variables.tf to set your SSH key name
nano opentofu/variables.tf
```

### Deploy the Template Infrastructure

```bash
# Load credentials (required before every tofu command)
source app-cred-openrc.sh

# Navigate to OpenTofu directory
cd opentofu

# Initialize OpenTofu (first time only)
tofu init

# Preview what will be created
tofu plan

# Create the infrastructure
tofu apply
# Type 'yes' when prompted

# Return to project root
cd ..
```

### Generate Ansible Inventory

After OpenTofu creates the servers, generate the Ansible inventory:

```bash
python3 import-tofu-to-ansible.py
```

This creates `ansible/inventory/production.ini` with all server details.

### Configure the Servers

Because of network restrictions, run Ansible from inside the cloud network. Use the fourth Linux server as your Ansible control node.

```bash
# Find the floating IP of the fourth Linux server
cat ansible/inventory/production.ini

# Copy ansible directory to that server
scp -r ansible cyberrange@<floating-ip>:~/

# SSH to the server
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<floating-ip>
# Password: Cyberrange123!

# Install Ansible on the control node
sudo apt update && sudo apt install -y ansible

# Run the main playbook
cd ansible
ansible-playbook playbooks/site.yml
```

This takes 30-60 minutes. It sets up the domain controller, joins all servers to the domain, and creates user accounts.

---

## Customizing for Your Competition

This template is a starting point. Your competition needs significant additions.

### Adding Network Segments

Your competition requires multiple network segments (DMZ, internal, management, Red Team). Edit `opentofu/network.tf` to add more networks:

```hcl
# Example: Adding a DMZ network
resource "openstack_networking_network_v2" "dmz_net" {
  name           = "competition-dmz-net"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "dmz_subnet" {
  name            = "competition-dmz-subnet"
  network_id      = openstack_networking_network_v2.dmz_net.id
  cidr            = "192.168.10.0/24"
  ip_version      = 4
  gateway_ip      = "192.168.10.1"
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}
```

### Adding Different Server Types

Edit `opentofu/instances.tf` to add new server types. Copy the existing patterns:

```hcl
# Example: Adding web servers
resource "openstack_compute_instance_v2" "web_servers" {
  count           = var.web_server_count
  name            = "web-${count.index + 1}"
  image_name      = var.debian_image
  flavor_name     = var.flavor
  key_name        = var.keypair_name
  security_groups = [openstack_networking_secgroup_v2.allow_all.name]
  user_data       = file("${path.module}/debian-userdata.yaml")

  network {
    uuid        = openstack_networking_network_v2.dmz_net.id
    fixed_ip_v4 = "192.168.10.${count.index + 10}"
  }
}
```

Add the variable in `variables.tf`:

```hcl
variable "web_server_count" {
  description = "Number of web servers to create"
  type        = number
  default     = 2
}
```

Add the output in `outputs.tf`:

```hcl
output "web_server_ips" {
  value = openstack_compute_instance_v2.web_servers[*].access_ip_v4
}
```

### Adding Team Workstations

Your competition requires dedicated workstations for each team member. Add them in `instances.tf`:

```hcl
# Blue Team workstations - one per team member
resource "openstack_compute_instance_v2" "blue_workstations" {
  count           = var.blue_team_size
  name            = "blue-ws-${count.index + 1}"
  image_name      = var.windows_image  # or debian for Linux workstations
  flavor_name     = var.flavor
  key_name        = var.keypair_name
  security_groups = [openstack_networking_secgroup_v2.allow_all.name]
  user_data       = file("${path.module}/windows-userdata.ps1")

  network {
    uuid        = openstack_networking_network_v2.internal_net.id
    fixed_ip_v4 = "192.168.20.${count.index + 101}"
  }
}

# Red Team workstations - one per team member
resource "openstack_compute_instance_v2" "red_workstations" {
  count           = var.red_team_size
  name            = "red-attack-${count.index + 1}"
  image_name      = "kali-2024"  # or your Kali image name
  flavor_name     = var.flavor
  key_name        = var.keypair_name
  security_groups = [openstack_networking_secgroup_v2.allow_all.name]

  network {
    uuid        = openstack_networking_network_v2.redteam_net.id
    fixed_ip_v4 = "192.168.100.${count.index + 101}"
  }
}
```

### Creating New Ansible Roles

For complex configurations, create Ansible roles. A role is a collection of related tasks, templates, and variables.

Create a new role directory structure:

```bash
mkdir -p ansible/roles/webserver/{tasks,templates,handlers,defaults}
```

Create the main task file at `ansible/roles/webserver/tasks/main.yml`:

```yaml
---
- name: Install Apache
  ansible.builtin.apt:
    name: apache2
    state: present
    update_cache: true

- name: Copy website configuration
  ansible.builtin.template:
    src: site.conf.j2
    dest: /etc/apache2/sites-available/competition.conf
  notify: Restart Apache

- name: Enable the site
  ansible.builtin.command: a2ensite competition
  notify: Restart Apache

- name: Ensure Apache is running
  ansible.builtin.service:
    name: apache2
    state: started
    enabled: true
```

Create the handler at `ansible/roles/webserver/handlers/main.yml`:

```yaml
---
- name: Restart Apache
  ansible.builtin.service:
    name: apache2
    state: restarted
```

Create a template at `ansible/roles/webserver/templates/site.conf.j2`:

```apache
<VirtualHost *:80>
    ServerName {{ inventory_hostname }}
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

Use the role in a playbook:

```yaml
---
- name: Configure Web Servers
  hosts: web_servers
  become: true
  roles:
    - webserver
```

### Adding Scored Services

Your competition needs a scoring engine. The scoring engine periodically checks if services are working and awards points. This is something you must build or adapt from existing tools.

Basic approach using Ansible for checks (simple but limited):

```yaml
# scoring-check.yml - run this periodically via cron
---
- name: Check Scored Services
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Check web server HTTP
      ansible.builtin.uri:
        url: "http://{{ web_server_ip }}/index.html"
        return_content: true
        status_code: 200
      register: web_check
      ignore_errors: true

    - name: Log web server status
      ansible.builtin.lineinfile:
        path: /var/log/scoring/web.log
        line: "{{ ansible_date_time.iso8601 }},{{ 'UP' if web_check.status == 200 else 'DOWN' }}"
        create: true
```

For a real competition, consider using or adapting:
- DWAYNE-INATOR-5000: https://github.com/DSU-DefSec/DWAYNE-INATOR-5000 (CCDC-style, service uptime scoring with SLA penalties)
- FAUST CTF Gameserver: https://github.com/fausecteam/ctf-gameserver (Attack/defend with flag submission)
- Custom Python scoring engine

### Modifying the Inventory Script

The `import-tofu-to-ansible.py` script generates Ansible inventory from OpenTofu output. When you add new server types, update this script to include them.

Read the script to understand its structure, then add sections for your new server types following the existing patterns.

---

## OpenTofu Basics

This section explains OpenTofu concepts you need to understand for customization.

### Directory Structure

```
opentofu/
  main.tf        - Provider configuration (OpenStack connection)
  variables.tf   - Input variables (things you can change)
  network.tf     - Network resources (networks, subnets, routers)
  instances.tf   - Compute instances (virtual machines)
  security.tf    - Security groups (firewall rules)
  outputs.tf     - Output values (information displayed after apply)
```

### Resources

A resource is something OpenTofu creates and manages. The syntax is:

```hcl
resource "TYPE" "NAME" {
  attribute = "value"
}
```

The TYPE determines what kind of resource (server, network, etc.). The NAME is your identifier for referencing it elsewhere.

Example:

```hcl
resource "openstack_compute_instance_v2" "my_server" {
  name        = "actual-server-name"
  image_name  = "debian-trixie-amd64-cloud"
  flavor_name = "medium"
}
```

### Variables

Variables let you customize values without editing resource definitions:

```hcl
# In variables.tf
variable "server_count" {
  description = "Number of servers to create"
  type        = number
  default     = 3
}

# In instances.tf
resource "openstack_compute_instance_v2" "servers" {
  count = var.server_count
  # ...
}
```

### Count and Indexing

The `count` parameter creates multiple identical resources:

```hcl
resource "openstack_compute_instance_v2" "servers" {
  count = 5
  name  = "server-${count.index + 1}"
  # Creates: server-1, server-2, server-3, server-4, server-5
}
```

Access items from counted resources using square brackets:

```hcl
# Reference the first server
openstack_compute_instance_v2.servers[0].access_ip_v4

# Reference all servers
openstack_compute_instance_v2.servers[*].access_ip_v4
```

### Outputs

Outputs display information after `tofu apply` runs:

```hcl
output "server_ips" {
  description = "IP addresses of all servers"
  value       = openstack_compute_instance_v2.servers[*].access_ip_v4
}
```

View outputs anytime with `tofu output`.

### Common Commands

```bash
# Load credentials first
source app-cred-openrc.sh

# Initialize (first time or after adding providers)
tofu init

# Preview changes
tofu plan

# Apply changes
tofu apply

# View current outputs
tofu output
tofu output -json  # JSON format for scripts

# Destroy everything
tofu destroy

# Destroy specific resource
tofu destroy -target=openstack_compute_instance_v2.servers[0]

# Force recreation of a resource
tofu taint openstack_compute_instance_v2.servers[0]
tofu apply
```

---

## Ansible Basics

This section explains Ansible concepts you need for customization.

### Directory Structure

```
ansible/
  ansible.cfg           - Ansible configuration
  inventory/
    production.ini      - Server list (auto-generated)
  group_vars/
    all.yml            - Variables for all servers
    windows.yml        - Variables for Windows servers
    linux_members.yml  - Variables for Linux servers
  playbooks/
    site.yml           - Main playbook (runs everything)
    setup-domain-controller.yml
    join-windows-domain.yml
    join-linux-domain.yml
    create-domain-users.yml
  roles/
    domain_controller/
    linux_domain_member/
    domain_users/
```

### Inventory

The inventory file lists servers and how to connect to them:

```ini
[web_servers]
web-1 ansible_host=192.168.10.10
web-2 ansible_host=192.168.10.11

[database_servers]
db-1 ansible_host=192.168.20.20

[web_servers:vars]
ansible_user=admin
ansible_password=secret
```

Groups are defined in square brackets. Servers are listed under their group. Variables for a group end with `:vars`.

### Playbooks

A playbook is a YAML file containing tasks to run:

```yaml
---
- name: Configure Web Servers
  hosts: web_servers      # Which servers to run on
  become: true            # Run as root/administrator

  tasks:
    - name: Install Apache
      ansible.builtin.apt:
        name: apache2
        state: present
```

Run a playbook:

```bash
ansible-playbook playbooks/my-playbook.yml
```

### Tasks

Tasks are individual actions. Each task uses a module:

```yaml
- name: Install a package
  ansible.builtin.apt:
    name: nginx
    state: present

- name: Copy a file
  ansible.builtin.copy:
    src: local-file.txt
    dest: /remote/path/file.txt

- name: Run a command
  ansible.builtin.command:
    cmd: systemctl restart nginx
```

### Variables

Variables can be defined in multiple places:

```yaml
# In group_vars/all.yml
domain_name: CDT.local
admin_password: Cyberrange123!

# In a playbook
vars:
  web_port: 80

# Used in tasks
- name: Configure domain
  ansible.builtin.debug:
    msg: "Domain is {{ domain_name }}"
```

### Handlers

Handlers run when notified by tasks:

```yaml
tasks:
  - name: Update Apache config
    ansible.builtin.template:
      src: apache.conf.j2
      dest: /etc/apache2/apache2.conf
    notify: Restart Apache

handlers:
  - name: Restart Apache
    ansible.builtin.service:
      name: apache2
      state: restarted
```

### Roles

Roles organize related tasks, templates, and variables:

```
roles/
  webserver/
    tasks/
      main.yml       - Tasks to run
    handlers/
      main.yml       - Handlers
    templates/
      site.conf.j2   - Template files
    defaults/
      main.yml       - Default variables
```

Use a role in a playbook:

```yaml
- name: Configure Servers
  hosts: web_servers
  roles:
    - webserver
```

### Common Commands

```bash
# Run a playbook
ansible-playbook playbooks/site.yml

# Run with more output
ansible-playbook playbooks/site.yml -v
ansible-playbook playbooks/site.yml -vvv  # Very verbose

# Run only on specific hosts
ansible-playbook playbooks/site.yml --limit web-1

# Check what would change without making changes
ansible-playbook playbooks/site.yml --check

# Test connectivity to all hosts
ansible all -m ping

# Run a single command on all hosts
ansible all -m command -a "whoami"

# Run a command on a specific group
ansible web_servers -m command -a "systemctl status apache2"
```

---

## Common Operations

### Changing Server Counts

Edit `opentofu/variables.tf`:

```hcl
variable "windows_count" {
  default = 5  # Changed from 3
}
```

Apply the change:

```bash
source app-cred-openrc.sh
cd opentofu
tofu plan
tofu apply
cd ..
python3 import-tofu-to-ansible.py
```

### Rebuilding a Single Server

Use the rebuild script:

```bash
./rebuild-vm.sh 10.10.10.21
```

This destroys and recreates only that server, then runs the appropriate Ansible playbook.

### Adding a New Service

1. Add the server in OpenTofu (edit `instances.tf`)
2. Run `tofu apply` to create it
3. Update `import-tofu-to-ansible.py` to include the new server in inventory
4. Run `python3 import-tofu-to-ansible.py`
5. Create an Ansible role for the service
6. Create a playbook that uses the role
7. Add the playbook to `site.yml`
8. Run the playbook

### Destroying Everything

```bash
source app-cred-openrc.sh
cd opentofu
tofu destroy
```

Type `yes` to confirm.

---

## Troubleshooting

### OpenTofu says "authentication required" or similar

You forgot to load credentials. Run:

```bash
source app-cred-openrc.sh
```

You must run this every time you open a new terminal.

### Ansible says "No hosts matched"

The inventory file is missing or empty. Generate it:

```bash
python3 import-tofu-to-ansible.py
```

### Ansible cannot connect to servers

Possible causes:

1. Servers are still booting. Windows takes 15-20 minutes. Wait and try again.
2. SSH jump host is not accessible. Test with: `ssh sshjump@ssh.cyberrange.rit.edu`
3. Wrong credentials. Check the inventory file for correct passwords.

### A server is broken and needs to be reset

Use the rebuild script:

```bash
./rebuild-vm.sh <ip-address>
```

### OpenTofu state is out of sync with reality

Refresh the state:

```bash
cd opentofu
source ../app-cred-openrc.sh
tofu refresh
```

### I made a mistake and need to start over

Destroy everything and recreate:

```bash
cd opentofu
source ../app-cred-openrc.sh
tofu destroy
tofu apply
cd ..
python3 import-tofu-to-ansible.py
# Then run Ansible again
```

---

## Next Steps for Your Competition

1. **Read the assignment requirements carefully** - Make sure you understand what infrastructure you need
2. **Design your network topology** - Draw it out before you start coding
3. **Extend this template** - Add networks, servers, and services as needed
4. **Create Ansible roles** - For each service type in your competition
5. **Build your scoring engine** - Test it thoroughly before competition day
6. **Test everything** - Deploy and destroy multiple times to verify it works
7. **Document everything** - Your documentation is part of the deliverable

The provided code demonstrates patterns you can follow. Study how the existing OpenTofu resources and Ansible roles are structured, then create your own following the same patterns.
