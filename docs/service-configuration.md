# Service Configuration Guide

This guide explains how to configure which services run on which boxes in your CTF infrastructure.

> **New to this?** See [Adding Services Guide](adding-services-guide.md) for beginner-friendly, step-by-step instructions with examples for each service type.

## Table of Contents

1. [Quick Start](#quick-start)
2. [How It Works](#how-it-works)
3. [Adding Services to a Box](#adding-services-to-a-box)
4. [Supported Services](#supported-services)
5. [Customizing Scoring Checks](#customizing-scoring-checks)
6. [Common Tasks](#common-tasks)
7. [Troubleshooting](#troubleshooting)

---

## Quick Start

**Goal:** Add a web server to your infrastructure and have it automatically scored.

**Step 1:** Add the hostname to OpenTofu (if new VM):

Edit `opentofu/variables.tf`:
```hcl
variable "blue_linux_hostnames" {
  default = ["webserver", "comms", "newbox"]  # Added newbox
}
```

**Step 2:** Assign services to the hostname:

Edit `opentofu/variables.tf`:
```hcl
variable "service_hosts" {
  default = {
    # ... existing services ...
    web = ["webserver", "newbox"]  # Added newbox to web service
  }
}
```

**Step 3:** Apply changes and regenerate inventory:

```bash
source app-cred-openrc.sh
cd opentofu && tofu apply
cd .. && python3 import-tofu-to-ansible.py
```

**Step 4:** Deploy the service and update scoring:

```bash
cd ansible
ansible-playbook playbooks/setup-web.yml           # Installs Apache
ansible-playbook playbooks/setup-scoring-engine.yml # Updates scoring config
```

Done! The new box now has web checks in the scoring engine.

---

## How It Works

The service configuration flows through three stages:

```
OpenTofu                    Inventory Script              Scoring Engine
---------                   ----------------              --------------
service_hosts = {     -->   [web]                   -->   [[box]]
  web = ["webserver"]       webserver                     name = "webserver"
}                           host_services='["web"]'       [[box.web]]
```

### Stage 1: OpenTofu (Source of Truth)

The `service_hosts` variable in `opentofu/variables.tf` defines which services run on which hosts:

```hcl
variable "service_hosts" {
  default = {
    web  = ["webserver"]      # webserver runs web
    ssh  = []                 # Empty = all Linux boxes
    dns  = ["dc01"]           # dc01 runs DNS
  }
}
```

### Stage 2: Inventory Generation

Running `python3 import-tofu-to-ansible.py` reads the service mappings and:

1. Creates Ansible groups for each service (`[web]`, `[dns]`, etc.)
2. Sets `host_services` variable on each host with its service list

Example inventory output:
```ini
[web]
webserver

[blue_linux]
webserver ansible_host=100.65.6.156 internal_ip=10.10.10.101 host_services='["ping","ssh","web"]'
```

### Stage 3: Scoring Engine

The scoring template (`dwayne.conf.j2`) reads each host's services and generates checks:

1. Looks up default check in `scoring_services.yml`
2. Applies any overrides from `scoring_overrides.yml`
3. Generates the `[[box]]` configuration

---

## Adding Services to a Box

### New Box with Services

1. Add hostname to `opentofu/variables.tf`:
   ```hcl
   variable "blue_linux_hostnames" {
     default = ["webserver", "comms", "mybox"]
   }
   ```

2. Add services in the same file:
   ```hcl
   variable "service_hosts" {
     default = {
       web = ["webserver", "mybox"]
       ftp = ["mybox"]
     }
   }
   ```

3. Apply and regenerate:
   ```bash
   cd opentofu && tofu apply
   cd .. && python3 import-tofu-to-ansible.py
   ```

### Existing Box, New Service

1. Add the hostname to the service list:
   ```hcl
   variable "service_hosts" {
     default = {
       mail = ["comms", "webserver"]  # Added webserver to mail
     }
   }
   ```

2. Regenerate inventory (no tofu apply needed):
   ```bash
   python3 import-tofu-to-ansible.py
   ```

---

## Supported Services

| Service | Check Type | Port | Credlist | Description |
|---------|------------|------|----------|-------------|
| `ping` | ICMP | - | - | Basic connectivity |
| `ssh` | SSH | 22 | linux_users | Linux remote access |
| `winrm` | WinRM | 5985 | admins | Windows remote management |
| `rdp` | RDP | 3389 | - | Windows remote desktop |
| `dns` | DNS | 53 | - | Name resolution |
| `ldap` | LDAP | 389 | - | Directory services |
| `smb` | TCP | 445 | - | Windows file sharing |
| `ftp` | FTP | 21 | linux_users | File transfer |
| `web` | HTTP | 80 | - | Web server |
| `sql` | MySQL | 3306 | linux_users | Database |
| `mail` | SMTP/IMAP | 25/143 | domain_users | Email |
| `irc` | TCP | 6667 | - | Chat server |
| `vnc` | VNC | 5900 | - | Linux remote desktop |

### Default Expansion

Some services expand to all applicable hosts when the list is empty:

| Service | Empty List Expands To |
|---------|----------------------|
| `ping` | All boxes |
| `ssh` | All Linux boxes |
| `winrm` | All Windows boxes |
| `rdp` | All Windows boxes |
| Others | No hosts (must be explicit) |

---

## Customizing Scoring Checks

### Override a Service Check

To customize how a service is checked on a specific box, edit `ansible/group_vars/scoring_overrides.yml`:

```yaml
scoring_box_overrides:
  webserver:
    web:
      - type: web
        urls:
          - path: "/"
            status: 200
          - path: "/api/health"
            status: 200
            regex: "ok"
```

This replaces the default web check for webserver only.

### Add Extra Checks (Flags)

To add checks without replacing defaults, use `extra_checks`:

```yaml
scoring_box_overrides:
  webserver:
    extra_checks:
      - type: ssh
        display: "flag"
        credlists: ["linux_users"]
        commands:
          - command: "cat /var/www/html/flag.txt"
            contains: true
            output: "{{ red_team_token }}"
```

### Modify Default Checks

To change the default check for ALL boxes with a service, edit `ansible/group_vars/scoring_services.yml`:

```yaml
service_check_defaults:
  web:
    - type: web
      urls:
        - path: "/"
          status: 200
        - path: "/robots.txt"
          status: 200
```

---

## Common Tasks

### See What Services a Box Has

Check the inventory:
```bash
grep "host_services" ansible/inventory/production.ini
```

### See All Boxes Running a Service

```bash
ansible web --list-hosts
```

### Test Service Connectivity

```bash
# Test all web servers
ansible web -m uri -a "url=http://{{ internal_ip }}"

# Test SSH on all Linux boxes
ansible ssh -m ping
```

### Preview Scoring Configuration

```bash
# Dry-run the scoring playbook to see generated config
ansible-playbook playbooks/setup-scoring-engine.yml --check --diff
```

---

## Troubleshooting

### Service Not Being Scored

**Checklist:**

1. Is the hostname in `service_hosts`?
   ```bash
   grep -A20 "service_hosts" opentofu/variables.tf
   ```

2. Was inventory regenerated?
   ```bash
   python3 import-tofu-to-ansible.py
   ```

3. Does the host have `host_services` set?
   ```bash
   grep "hostname" ansible/inventory/production.ini
   ```

4. Is there a check defined in `scoring_services.yml`?
   ```bash
   grep "servicename:" ansible/group_vars/scoring_services.yml
   ```

### Check Not Using Custom Override

**Verify override syntax:**

```yaml
# WRONG - missing list wrapper
scoring_box_overrides:
  mybox:
    web:
      type: web  # Should be a list!

# CORRECT
scoring_box_overrides:
  mybox:
    web:
      - type: web  # List of checks
```

### Inventory Shows Empty host_services

**Ensure hostname matches exactly:**

```hcl
# In variables.tf
blue_linux_hostnames = ["WebServer"]  # Capital W

# In service_hosts
web = ["webserver"]  # Lowercase - NO MATCH!
```

Hostnames are case-sensitive. Use consistent casing.

---

## File Reference

| File | Purpose |
|------|---------|
| `opentofu/variables.tf` | Source of truth for service assignments |
| `import-tofu-to-ansible.py` | Generates inventory from OpenTofu |
| `ansible/inventory/production.ini` | Generated inventory with service groups |
| `ansible/group_vars/scoring_services.yml` | Default check definitions |
| `ansible/group_vars/scoring_overrides.yml` | Per-box customizations |
| `ansible/roles/scoring_engine/templates/dwayne.conf.j2` | Scoring config template |
