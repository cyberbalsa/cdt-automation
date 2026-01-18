# CDT Automation - Competition Infrastructure Template

This project provides a starting point for Grey Teams building attack/defend cybersecurity competition infrastructure. It demonstrates how to use OpenTofu (Terraform) for creating cloud resources and Ansible for configuring servers.

Use this as a foundation. You will need to modify and extend it significantly to meet your competition's requirements.

---

## Table of Contents

1. [What This Template Provides](#what-this-template-provides)
2. [Architecture Overview](#architecture-overview)
3. [Understanding the Tools](#understanding-the-tools)
4. [Prerequisites](#prerequisites)
5. [Quick Start](#quick-start)
6. [Customizing for Your Competition](#customizing-for-your-competition)
7. [OpenTofu Basics](#opentofu-basics)
8. [Ansible Basics](#ansible-basics)
9. [Common Operations](#common-operations)
10. [Troubleshooting](#troubleshooting)

---

## What This Template Provides

This template creates infrastructure across three OpenStack projects:

| Project | Contents | Purpose |
|---------|----------|---------|
| Main (Grey Team) | Network, router, scoring servers | You control the network and run scoring |
| Blue (Blue Team) | Windows DC, Windows members, Linux servers | Defenders access these machines |
| Red (Red Team) | Kali attack boxes | Attackers access these machines |

The template demonstrates a multi-project architecture where:

- Grey Team owns the network infrastructure
- Blue Team and Red Team VMs run in separate projects for access control
- All VMs communicate on a shared network (10.10.10.0/24)
- Each team can only see and manage their own servers in OpenStack

This is NOT a complete competition environment. It is a starting point that demonstrates the patterns you will use to build your own infrastructure. Your competition will likely need:

- Additional network segments (DMZ, internal, management)
- More services (web servers, mail servers, databases, etc.)
- Custom vulnerabilities and flags
- A scoring engine with service checks
- Firewall/router between network segments

---

## Architecture Overview

### Multi-Project Structure

```
                         INTERNET
                             |
                        [MAIN-NAT]          External network (100.65.0.0/16)
                             |
                       [cdt_router]         Router (main project)
                             |
                       [cdt_subnet]         10.10.10.0/24 (main project)
                             |
        +--------------------+--------------------+--------------------+
        |                    |                    |                    |
   [Scoring]            [Blue Team]          [Blue Team]          [Red Team]
   10.10.10.1x          Windows              Linux                Kali
   Main Project         10.10.10.2x          10.10.10.3x          10.10.10.4x
                        Blue Project         Blue Project         Red Project
```

### How Network Sharing Works

The network and subnet exist in the main (Grey Team) project. OpenStack RBAC (Role-Based Access Control) policies share the network with the Blue and Red projects:

```
Main Project                    Blue Project              Red Project
+------------------+           +----------------+        +----------------+
| cdt_net          |  shared   | (can attach    |        | (can attach    |
| cdt_subnet       | --------> |  VMs to net)   |        |  VMs to net)   |
| cdt_router       |  via      |                |        |                |
| RBAC policies    |  RBAC     | blue_windows   |        | red_kali       |
| scoring VMs      |           | blue_linux     |        |                |
+------------------+           +----------------+        +----------------+
```

This architecture means:

- Grey Team controls the network (can see all traffic, manage routing)
- Blue Team can only see their own VMs in OpenStack
- Red Team can only see their own VMs in OpenStack
- All VMs can communicate because they share the same network

### IP Address Scheme

| Range | Team | Purpose | Project |
|-------|------|---------|---------|
| 10.10.10.11-19 | Grey | Scoring servers | Main |
| 10.10.10.21-29 | Blue | Windows servers (DC at .21) | Blue |
| 10.10.10.31-39 | Blue | Linux servers | Blue |
| 10.10.10.41-49 | Red | Kali attack boxes | Red |

The first Blue Windows server (10.10.10.21) becomes the Active Directory Domain Controller.

### What Gets Created

**Main Project (Grey Team):**
- Virtual network (10.10.10.0/24)
- Subnet with DHCP disabled (fixed IPs only)
- Router connected to external network
- RBAC policies sharing network with Blue and Red projects
- Scoring server(s) running Ubuntu Desktop

**Blue Project (Blue Team):**
- Windows Server(s) - first one becomes Domain Controller
- Linux server(s) - joined to the domain
- Security groups for Windows and Linux

**Red Project (Red Team):**
- Kali Linux attack boxes with xRDP
- Security group for Linux

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

## Prerequisites

Before you begin, you need:

- Three OpenStack project names from your instructor (main, blue, red)
- Required software installed (Git, OpenTofu, Ansible, Python 3)
- An RSA SSH key pair uploaded to OpenStack

For detailed setup instructions, see [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md).

---

## Quick Start

For experienced users who know OpenTofu and Ansible:

```bash
# 1. Clone and enter the repository
git clone <your-repo-url>
cd cdt-automation

# 2. Move your openrc file here and run setup
mv ~/Downloads/app-cred-*-openrc.sh .
./quick-start.sh

# 3. Edit variables.tf with your project IDs and SSH key name
nano opentofu/variables.tf

# 4. Deploy infrastructure
source app-cred-openrc.sh
cd opentofu
tofu plan
tofu apply
cd ..

# 5. Generate inventory and run Ansible
python3 import-tofu-to-ansible.py

# 6. Copy ansible to a control node and run playbooks
scp -r -J sshjump@ssh.cyberrange.rit.edu ansible/ cyberrange@<linux-ip>:~/
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<linux-ip>
# On the control node:
sudo apt update && sudo apt install -y ansible
cd ~/ansible && ansible-playbook playbooks/site.yml
```

For step-by-step instructions, see [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md).

---

## Customizing for Your Competition

This template is a starting point. Your competition needs significant additions.

### Adding Network Segments

Your competition likely requires multiple network segments (DMZ, internal, management). Edit `opentofu/network.tf` to add more networks:

```hcl
# Example: Adding a DMZ network
resource "openstack_networking_network_v2" "dmz_net" {
  provider       = openstack.main
  name           = "competition-dmz-net"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "dmz_subnet" {
  provider        = openstack.main
  name            = "competition-dmz-subnet"
  network_id      = openstack_networking_network_v2.dmz_net.id
  cidr            = "192.168.10.0/24"
  ip_version      = 4
  gateway_ip      = "192.168.10.1"
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}
```

Note the `provider = openstack.main` line. In this multi-project setup, you must specify which project should own each resource.

### Adding Different Server Types

Edit `opentofu/instances.tf` to add new server types. Specify the correct provider for each:

```hcl
# Example: Adding web servers to Blue Team
resource "openstack_compute_instance_v2" "blue_webservers" {
  provider        = openstack.blue
  count           = var.blue_webserver_count
  name            = "web-${count.index + 1}"
  image_name      = var.debian_image
  flavor_name     = var.flavor
  key_name        = var.keypair_name
  security_groups = [openstack_networking_secgroup_v2.blue_linux_sg.name]
  user_data       = file("${path.module}/debian-userdata.yaml")

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.5${count.index + 1}"
  }
}
```

Add the variable in `variables.tf`:

```hcl
variable "blue_webserver_count" {
  description = "Number of Blue Team web servers"
  type        = number
  default     = 2
}
```

Add the output in `outputs.tf`:

```hcl
output "blue_webserver_ips" {
  description = "Blue Team web server IPs"
  value = {
    names        = openstack_compute_instance_v2.blue_webservers[*].name
    internal_ips = openstack_compute_instance_v2.blue_webservers[*].access_ip_v4
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

Use the role in a playbook targeting the correct inventory group:

```yaml
---
- name: Configure Web Servers
  hosts: blue_webservers
  become: true
  roles:
    - webserver
```

### Adding Scored Services

Your competition needs a scoring engine. The scoring engine periodically checks if services are working and awards points. This is something you must build or adapt from existing tools.

For a real competition, consider using or adapting:

- DWAYNE-INATOR-5000: https://github.com/DSU-DefSec/DWAYNE-INATOR-5000 (CCDC-style, service uptime scoring)
- FAUST CTF Gameserver: https://github.com/fausecteam/ctf-gameserver (Attack/defend with flag submission)
- Custom Python scoring engine

### Modifying the Inventory Script

The `import-tofu-to-ansible.py` script generates Ansible inventory from OpenTofu output. When you add new server types, update this script to include them.

The script reads `tofu output -json` and creates inventory groups. Add sections for your new server types following the existing patterns.

---

## OpenTofu Basics

This section explains OpenTofu concepts you need to understand for customization.

### Directory Structure

```
opentofu/
  main.tf        - Provider configuration (OpenStack connection, project aliases)
  variables.tf   - Input variables (things you can change)
  network.tf     - Network resources (networks, subnets, routers, RBAC policies)
  instances.tf   - Compute instances (virtual machines)
  security.tf    - Security groups (firewall rules)
  outputs.tf     - Output values (information displayed after apply)
```

### Provider Aliases

This project uses multiple OpenStack providers to deploy to different projects:

```hcl
provider "openstack" {
  alias     = "main"
  tenant_id = var.main_project_id
  # ... other settings
}

provider "openstack" {
  alias     = "blue"
  tenant_id = var.blue_project_id
  # ... other settings
}

provider "openstack" {
  alias     = "red"
  tenant_id = var.red_project_id
  # ... other settings
}
```

When creating resources, specify which project should own them:

```hcl
# This VM will be created in the Blue project
resource "openstack_compute_instance_v2" "blue_linux" {
  provider = openstack.blue
  # ...
}
```

### Resources

A resource is something OpenTofu creates and manages. The syntax is:

```hcl
resource "TYPE" "NAME" {
  provider  = openstack.PROJECT  # Which project
  attribute = "value"
}
```

The TYPE determines what kind of resource (server, network, etc.). The NAME is your identifier for referencing it elsewhere.

### Variables

Variables let you customize values without editing resource definitions:

```hcl
# In variables.tf
variable "blue_linux_count" {
  description = "Number of Blue Team Linux servers"
  type        = number
  default     = 2
}

# In instances.tf
resource "openstack_compute_instance_v2" "blue_linux" {
  provider = openstack.blue
  count    = var.blue_linux_count
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
tofu destroy -target=openstack_compute_instance_v2.blue_linux[0]

# Force recreation of a resource
tofu taint openstack_compute_instance_v2.blue_linux[0]
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
    setup-rdp-linux.yml
    setup-rdp-windows.yml
  roles/
    domain_controller/
    linux_domain_member/
    domain_users/
```

### Inventory Groups

The auto-generated inventory organizes servers by team:

```ini
[scoring]
# Grey Team scoring servers

[windows_dc]
# First Blue Windows server (Domain Controller)

[blue_windows_members]
# Blue Windows servers except DC

[blue_linux_members]
# Blue Linux servers

[red_team]
# Red Team Kali boxes

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

Target specific teams in playbooks:

```yaml
# Run on all Blue Team servers
- hosts: blue_team

# Run on Red Team only
- hosts: red_team

# Run on all Windows servers
- hosts: windows
```

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
ansible blue_team -m command -a "hostname"
```

---

## Common Operations

### Changing Server Counts

Edit `opentofu/variables.tf`:

```hcl
variable "blue_linux_count" {
  default = 4  # Changed from 2
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
./rebuild-vm.sh 10.10.10.31
```

This destroys and recreates only that server, then runs the appropriate Ansible playbook.

### Adding a New Service

1. Add the server in OpenTofu (edit `instances.tf`, use correct provider)
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

Type `yes` to confirm. This destroys resources in all three projects.

---

## Troubleshooting

### OpenTofu says "authentication required" or similar

You forgot to load credentials. Run:

```bash
source app-cred-openrc.sh
```

You must run this every time you open a new terminal.

### OpenTofu says "could not find project" or similar

Your project IDs in `variables.tf` are incorrect. Double-check them in the OpenStack dashboard:

1. Log into OpenStack
2. Go to Identity, then Projects
3. Verify the IDs match exactly (they are case-sensitive)

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

### RBAC errors when creating Blue or Red VMs

The network sharing might have failed. Check:

1. The main project's network exists
2. RBAC policies were created (check in OpenTofu state)
3. Your credential has access to all three projects

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

See [STUDENT-CHECKLIST.md](STUDENT-CHECKLIST.md) for a detailed checklist of tasks to complete.
