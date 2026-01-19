# Service Mapping System Design

**Date:** 2026-01-19
**Status:** Approved
**Author:** Grey Team

## Overview

This document describes the design for an automated service-to-host mapping system. The goal is to define services once in OpenTofu and have them automatically flow through to Ansible inventory groups and the scoring engine configuration.

### Problem Statement

Currently, service configuration is scattered across multiple files:

1. **OpenTofu** (`variables.tf`) - Defines VM names and counts, but nothing about services
2. **Inventory** (`production.ini`) - Groups VMs by type (windows, linux), but no service groups
3. **Services config** (`group_vars/services.yml`) - Says "add hosts to [web], [ftp] groups" but those groups are never auto-generated
4. **Scoring config** (`group_vars/scoring.yml`) - Contains hardcoded `scoring_boxes` with manually defined checks

When you add a VM or change hostnames, you must manually update multiple files. This is error-prone and confusing for new team members.

### Solution

Define a `service_hosts` variable in OpenTofu that maps services to hostnames. The inventory generation script reads this and:

1. Creates service-based Ansible groups (`[web]`, `[ftp]`, `[ssh]`, etc.)
2. Sets `host_services` variable on each host listing its services
3. The scoring engine template auto-generates `scoring_boxes` from this data

Custom checks (flag validations, specific DNS records) are defined in a separate overrides file.

## Detailed Design

### 1. OpenTofu Service Definitions

**File:** `opentofu/variables.tf`

Add a new variable that maps service names to the hostnames that run them:

```hcl
variable "service_hosts" {
  description = "Map of services to the hostnames that run them. Empty list means apply default logic."
  type        = map(list(string))
  default = {
    # Core services - empty list means "apply to all applicable hosts"
    # ping  = []  -> all boxes get ping checks
    # ssh   = []  -> all Linux boxes get SSH checks
    # winrm = []  -> all Windows boxes get WinRM checks
    # rdp   = []  -> all Windows boxes get RDP checks
    ping  = []
    ssh   = []
    winrm = []
    rdp   = []

    # Explicit service assignments - list the hostnames that run each service
    dns  = ["dc01"]
    web  = ["webserver"]
    ftp  = ["webserver"]
    smb  = ["dc01", "wks-alpha"]
    sql  = ["comms"]
    mail = ["comms"]
    irc  = ["comms"]
    vnc  = []
    ldap = ["dc01"]
  }
}
```

**File:** `opentofu/outputs.tf`

Export the service mappings so the inventory script can read them:

```hcl
output "service_hosts" {
  description = "Service to hostname mappings for Ansible inventory generation"
  value       = var.service_hosts
}
```

#### Default Expansion Logic

When a service has an empty list `[]`, the inventory script applies default logic:

| Service | If list is empty, apply to... |
|---------|-------------------------------|
| `ping`  | All boxes (scoring + blue_windows + blue_linux) |
| `ssh`   | All `blue_linux` hosts |
| `winrm` | All `blue_windows` hosts |
| `rdp`   | All `blue_windows` hosts |
| All others | No hosts (must be explicitly listed) |

This means you do not need to list every Linux host under `ssh` - it happens automatically.

### 2. Supported Services

The following services are supported out of the box:

| Service | Check Type | Default Port | Description |
|---------|------------|--------------|-------------|
| `ping`  | ICMP ping  | -            | Basic connectivity check |
| `ssh`   | SSH login  | 22           | Linux remote access |
| `winrm` | WinRM login | 5985        | Windows remote management |
| `rdp`   | RDP available | 3389      | Windows remote desktop |
| `dns`   | DNS resolution | 53        | Name server queries |
| `web`   | HTTP response | 80         | Web server check |
| `ftp`   | FTP connection | 21        | File transfer protocol |
| `smb`   | TCP check  | 445          | Windows file sharing |
| `sql`   | MySQL/MariaDB | 3306      | Database connectivity |
| `mail`  | SMTP + IMAP | 25, 143     | Email server |
| `irc`   | TCP check  | 6667         | IRC chat server |
| `vnc`   | VNC connection | 5900      | Remote desktop (Linux) |
| `ldap`  | LDAP query | 389          | Directory services |

### 3. Inventory Generation Changes

**File:** `import-tofu-to-ansible.py`

The script will be updated to:

1. Read `service_hosts` from OpenTofu output
2. Apply default expansion logic for empty lists
3. Generate service-based Ansible groups
4. Set `host_services` variable on each host

#### Generated Inventory Structure

```ini
# ---------------------------------------------------------------------------
# SERVICE GROUPS (auto-generated from OpenTofu service_hosts)
# ---------------------------------------------------------------------------
# These groups are created automatically based on the service_hosts variable
# in opentofu/variables.tf. Use them to target playbooks at specific services.
#
# Example: ansible-playbook playbooks/setup-web.yml
# This automatically runs against all hosts in the [web] group.

[ping]
dc01
wks-alpha
webserver
comms

[ssh]
webserver
comms
blue-linux-3
blue-linux-4
blue-linux-5

[winrm]
dc01
wks-alpha
wks-debbie
blue-win-4

[rdp]
dc01
wks-alpha
wks-debbie
blue-win-4

[web]
webserver

[dns]
dc01

[ftp]
webserver

[smb]
dc01
wks-alpha

[sql]
comms

[mail]
comms

[irc]
comms

[ldap]
dc01
```

#### Host Services Variable

Each host will have a `host_services` variable listing all services assigned to it:

```ini
[blue_linux]
webserver ansible_host=100.65.6.156 internal_ip=10.10.10.101 host_services='["ping","ssh","web","ftp"]'
comms ansible_host=100.65.3.42 internal_ip=10.10.10.102 host_services='["ping","ssh","sql","mail","irc"]'
```

This variable is used by the scoring engine template to generate checks.

### 4. Scoring Engine Configuration

The scoring configuration is split into three files:

#### File: `ansible/group_vars/scoring.yml`

Contains event settings, teams, and credential lists. The `scoring_boxes` section is REMOVED - it will be auto-generated.

```yaml
# Event settings (unchanged)
scoring_event_name: "CDT Attack/Defend Competition"
scoring_timezone: "America/New_York"
# ... etc

# Teams (unchanged)
scoring_teams:
  - id: "1"
    password: "BlueTeam123!"

# Credential lists (unchanged)
scoring_credlists:
  - name: "domain_users"
    usernames: [jdoe, asmith, bwilson, mjohnson, dlee]
    default_password: "UserPass123!"
  # ... etc

# NOTE: scoring_boxes is now auto-generated from service_hosts
# See scoring_services.yml for default checks
# See scoring_overrides.yml for custom checks
```

#### File: `ansible/group_vars/scoring_services.yml` (NEW)

Defines the default scoring check for each service type:

```yaml
# ==============================================================================
# SERVICE CHECK DEFAULTS
# ==============================================================================
# This file maps service names to their default scoring engine checks.
# When a host has a service assigned, these checks are automatically added.
#
# To customize checks for a specific host, use scoring_overrides.yml instead.
# ==============================================================================

service_check_defaults:
  ping:
    - type: ping

  ssh:
    - type: ssh
      credlists: ["linux_users"]

  winrm:
    - type: winrm
      credlists: ["admins"]

  rdp:
    - type: rdp

  web:
    - type: web
      urls:
        - path: "/"
          status: 200

  dns:
    - type: dns
    # Note: DNS records must be defined in scoring_overrides.yml per-box

  smb:
    - type: tcp
      port: 445

  sql:
    - type: sql
      credlists: ["linux_users"]
      queries:
        - database: "scoring_test"
          databaseexists: true

  mail:
    - type: smtp
    - type: imap
      credlists: ["domain_users"]

  irc:
    - type: tcp
      port: 6667

  ftp:
    - type: ftp
      credlists: ["linux_users"]

  vnc:
    - type: vnc

  ldap:
    - type: ldap
```

#### File: `ansible/group_vars/scoring_overrides.yml` (NEW)

Defines per-box customizations and extra checks (like flag validations):

```yaml
# ==============================================================================
# SCORING BOX OVERRIDES
# ==============================================================================
# Use this file to customize auto-generated checks for specific boxes.
#
# OVERRIDE A SERVICE CHECK:
# If you define a service key (like "web" or "dns"), it completely replaces
# the default check from scoring_services.yml.
#
# ADD EXTRA CHECKS:
# Use "extra_checks" to append additional checks (like flag validations)
# without removing the auto-generated ones.
# ==============================================================================

scoring_box_overrides:
  # --------------------------------------------------------------------------
  # DOMAIN CONTROLLER (dc01)
  # --------------------------------------------------------------------------
  dc01:
    # DNS needs specific records to check
    dns:
      - type: dns
        records:
          - kind: "A"
            domain: "dc01.CDT.local"
            answer: ["{{ hostvars['dc01']['internal_ip'] }}"]
          - kind: "A"
            domain: "CDT.local"
            answer: ["{{ hostvars['dc01']['internal_ip'] }}"]

    # Flag check for Red Team scoring
    extra_checks:
      - type: winrm
        display: "flag"
        credlists: ["admins"]
        commands:
          - command: "Get-Content C:\\Users\\Public\\flag.txt"
            contains: true
            output: "{{ red_team_token }}"

  # --------------------------------------------------------------------------
  # WEB SERVER (webserver)
  # --------------------------------------------------------------------------
  webserver:
    # Custom web paths to check
    web:
      - type: web
        urls:
          - path: "/"
            status: 200
          - path: "/index.html"
            status: 200

    extra_checks:
      - type: ssh
        display: "flag"
        credlists: ["linux_users"]
        commands:
          - command: "cat /var/www/html/flag.txt 2>/dev/null || echo NOT_FOUND"
            contains: true
            output: "{{ red_team_token }}"

  # --------------------------------------------------------------------------
  # COMMUNICATIONS SERVER (comms)
  # --------------------------------------------------------------------------
  comms:
    extra_checks:
      - type: ssh
        display: "flag"
        credlists: ["linux_users"]
        commands:
          - command: "cat /home/flag.txt 2>/dev/null || echo NOT_FOUND"
            contains: true
            output: "{{ red_team_token }}"
```

### 5. Template Generation Logic

**File:** `ansible/roles/scoring_engine/templates/dwayne.conf.j2`

The template builds `scoring_boxes` dynamically using this logic:

```
For each host that has services assigned:
  1. Create a [[box]] entry with name and IP
  2. For each service on the host:
     a. Check if scoring_box_overrides has a custom definition
     b. If yes, use the override
     c. If no, use the default from service_check_defaults
  3. Append any extra_checks from scoring_box_overrides
```

#### Merge Priority

1. **Override wins** - If `scoring_box_overrides.dc01.dns` exists, it completely replaces the default DNS check
2. **Defaults apply** - Services without overrides use `service_check_defaults`
3. **Extra checks append** - `extra_checks` are always added after service checks

### 6. Data Flow Diagram

```
+------------------+
| OpenTofu         |
| variables.tf     |
|                  |
| service_hosts = {|
|   web: [websvr]  |
|   ssh: []        |
| }                |
+--------+---------+
         |
         | tofu output -json
         v
+------------------+
| import-tofu-     |
| to-ansible.py    |
|                  |
| - Reads services |
| - Expands empty  |
|   lists          |
| - Generates      |
|   groups         |
+--------+---------+
         |
         | writes
         v
+------------------+     +----------------------+
| inventory/       |     | group_vars/          |
| production.ini   |     |                      |
|                  |     | scoring_services.yml |
| [web]            |     | (default checks)     |
| webserver        |     |                      |
|                  |     | scoring_overrides.yml|
| host_services=   |     | (custom checks)      |
| ["ping","ssh",   |     +----------+-----------+
|  "web","ftp"]    |                |
+--------+---------+                |
         |                          |
         |  ansible-playbook        |
         |  setup-scoring-engine.yml|
         v                          v
+----------------------------------------+
| dwayne.conf.j2 template                |
|                                        |
| - Iterates hosts with services         |
| - Looks up defaults/overrides          |
| - Generates [[box]] entries            |
+----------------------------------------+
         |
         | renders to
         v
+------------------+
| dwayne.conf      |
| (scoring engine) |
+------------------+
```

## Files Changed

### New Files

| File | Purpose |
|------|---------|
| `docs/plans/2026-01-19-service-mapping-design.md` | This design document |
| `docs/service-configuration.md` | User guide for service system |
| `ansible/group_vars/scoring_services.yml` | Default check templates per service |
| `ansible/group_vars/scoring_overrides.yml` | Per-box custom checks |

### Modified Files

| File | Changes |
|------|---------|
| `opentofu/variables.tf` | Add `service_hosts` variable |
| `opentofu/outputs.tf` | Add `service_hosts` output |
| `import-tofu-to-ansible.py` | Read services, generate groups, set host_services |
| `ansible/roles/scoring_engine/templates/dwayne.conf.j2` | Dynamic box generation from services |
| `ansible/group_vars/scoring.yml` | Remove hardcoded `scoring_boxes` |

### Moved Files

| From | To |
|------|-----|
| `scoring/README.md` | `docs/scoring-engine.md` |

## Example Workflow

### Adding a New Web Server

1. **Add the hostname** in `opentofu/variables.tf`:
   ```hcl
   variable "blue_linux_hostnames" {
     default = ["webserver", "comms", "webserver2"]  # Added webserver2
   }
   ```

2. **Assign services** in the same file:
   ```hcl
   variable "service_hosts" {
     default = {
       # ...
       web = ["webserver", "webserver2"]  # Added webserver2
       ftp = ["webserver", "webserver2"]  # Added webserver2
       # ...
     }
   }
   ```

3. **Deploy and regenerate**:
   ```bash
   cd opentofu && tofu apply
   cd .. && python3 import-tofu-to-ansible.py
   ```

4. **Run playbooks**:
   ```bash
   cd ansible
   ansible-playbook playbooks/setup-web.yml  # Auto-targets [web] group
   ansible-playbook playbooks/setup-scoring-engine.yml  # Regenerates scoring config
   ```

The new server automatically appears in:
- `[web]` and `[ftp]` inventory groups
- Scoring engine with default web and FTP checks
- No manual editing of scoring.yml required

### Adding a Flag Check

1. **Edit** `ansible/group_vars/scoring_overrides.yml`:
   ```yaml
   scoring_box_overrides:
     webserver2:
       extra_checks:
         - type: ssh
           display: "flag"
           credlists: ["linux_users"]
           commands:
             - command: "cat /var/www/html/flag.txt 2>/dev/null || echo NOT_FOUND"
               contains: true
               output: "{{ red_team_token }}"
   ```

2. **Regenerate scoring config**:
   ```bash
   ansible-playbook playbooks/setup-scoring-engine.yml
   ```

## Testing Plan

1. Verify OpenTofu outputs include `service_hosts`
2. Verify inventory script generates correct service groups
3. Verify `host_services` variable is set on each host
4. Verify scoring template generates expected `[[box]]` entries
5. Verify overrides replace default checks correctly
6. Verify extra_checks are appended correctly
7. End-to-end: Add a new host with services, verify it appears in scoring
