# Service Mapping System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Define services once in OpenTofu and have them automatically flow through to Ansible inventory groups and scoring engine configuration.

**Architecture:** OpenTofu `service_hosts` variable maps services to hostnames. The inventory script reads this, generates service-based Ansible groups, and sets `host_services` per host. The scoring template uses this data plus defaults/overrides to auto-generate `scoring_boxes`.

**Tech Stack:** OpenTofu (HCL), Python (inventory script), Ansible (YAML/Jinja2)

---

## Prerequisites

- Working directory: `/root/cdt-automation/.worktrees/service-mapping`
- Branch: `feature/service-mapping`
- Design document: `docs/plans/2026-01-19-service-mapping-design.md`

---

## Task 1: Add service_hosts Variable to OpenTofu

**Files:**
- Modify: `opentofu/variables.tf` (append to end)
- Modify: `opentofu/outputs.tf` (append to end)

**Step 1: Add service_hosts variable**

Add to end of `opentofu/variables.tf`:

```hcl
# ------------------------------------------------------------------------------
# SERVICE CONFIGURATION
# ------------------------------------------------------------------------------
# Map services to the hostnames that run them. This flows through to:
# 1. Ansible inventory groups ([web], [ftp], [ssh], etc.)
# 2. Scoring engine box configurations
#
# EMPTY LIST BEHAVIOR:
# - ping  = [] -> All boxes get ping checks
# - ssh   = [] -> All Linux boxes get SSH checks
# - winrm = [] -> All Windows boxes get WinRM/RDP checks
# - rdp   = [] -> All Windows boxes get RDP checks
# - Other services must be explicitly assigned
#
# EXAMPLE: To add a new web server:
# 1. Add hostname to blue_linux_hostnames
# 2. Add hostname to the "web" list below
# 3. Run: tofu apply && python3 import-tofu-to-ansible.py

variable "service_hosts" {
  description = "Map of services to the hostnames that run them"
  type        = map(list(string))
  default = {
    # Core services (empty = apply to all applicable hosts)
    ping  = []
    ssh   = []
    winrm = []
    rdp   = []

    # Network services
    dns  = ["dc01"]
    ldap = ["dc01"]

    # File services
    smb = ["dc01", "wks-alpha"]
    ftp = ["webserver"]

    # Application services
    web  = ["webserver"]
    sql  = ["comms"]
    mail = ["comms"]
    irc  = ["comms"]
    vnc  = []
  }
}
```

**Step 2: Add service_hosts output**

Add to end of `opentofu/outputs.tf`:

```hcl
# ------------------------------------------------------------------------------
# SERVICE CONFIGURATION OUTPUT
# ------------------------------------------------------------------------------
# Exports service mappings for the inventory generation script.
# The script reads this to create Ansible service groups.

output "service_hosts" {
  description = "Service to hostname mappings for Ansible inventory generation"
  value       = var.service_hosts
}
```

**Step 3: Validate OpenTofu syntax**

Run:
```bash
cd opentofu && tofu validate
```

Expected: `Success! The configuration is valid.`

**Step 4: Run tflint**

Run:
```bash
cd opentofu && tflint
```

Expected: No errors (warnings about unused variables are OK)

**Step 5: Commit**

```bash
git add opentofu/variables.tf opentofu/outputs.tf
git commit -m "feat(tofu): add service_hosts variable for service-to-host mapping

Defines which services run on which hosts. Empty lists trigger default
expansion (ping->all, ssh->linux, winrm/rdp->windows).

Part of service mapping system - see docs/plans/2026-01-19-service-mapping-design.md"
```

---

## Task 2: Update Inventory Script - Parse Services

**Files:**
- Modify: `import-tofu-to-ansible.py`

**Step 1: Add service parsing after existing data extraction**

Find this section (around line 125-145):
```python
    # Red Team Kali VMs
    red_kali_names = tofu_data.get('red_kali_names', {}).get('value', [])
```

Add after it:

```python

    # ===========================================================================
    # SERVICE CONFIGURATION
    # ===========================================================================
    # Read service-to-host mappings from OpenTofu output.
    # Empty lists get expanded to default hosts based on OS type.

    service_hosts = tofu_data.get('service_hosts', {}).get('value', {})

    # Build lookup sets for default expansion
    all_linux_hosts = set(scoring_names + blue_linux_names)
    all_windows_hosts = set(blue_windows_names)
    all_hosts = all_linux_hosts | all_windows_hosts

    # Expand empty service lists to defaults
    expanded_services = {}
    for service, hosts in service_hosts.items():
        if hosts:  # Explicit host list provided
            expanded_services[service] = hosts
        elif service == 'ping':
            expanded_services[service] = list(all_hosts)
        elif service in ('ssh',):
            expanded_services[service] = list(all_linux_hosts)
        elif service in ('winrm', 'rdp'):
            expanded_services[service] = list(all_windows_hosts)
        else:
            expanded_services[service] = []  # No default for other services

    # Build reverse mapping: hostname -> list of services
    host_to_services = {}
    for service, hosts in expanded_services.items():
        for host in hosts:
            if host not in host_to_services:
                host_to_services[host] = []
            host_to_services[host].append(service)

    # Sort services for consistent output
    for host in host_to_services:
        host_to_services[host].sort()
```

**Step 2: Verify script syntax**

Run:
```bash
python3 -m py_compile import-tofu-to-ansible.py && echo "Syntax OK"
```

Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add import-tofu-to-ansible.py
git commit -m "feat(inventory): parse service_hosts from OpenTofu output

Reads service mappings and expands empty lists to defaults:
- ping -> all hosts
- ssh -> all Linux hosts
- winrm/rdp -> all Windows hosts

Builds host_to_services reverse mapping for per-host service lists."
```

---

## Task 3: Update Inventory Script - Generate Service Groups

**Files:**
- Modify: `import-tofu-to-ansible.py`

**Step 1: Add service groups generation**

Find this section in the `create_inventory` function (around line 265-275):
```python
        # All VMs in the competition
        f.write("# All VMs in the CTF\n")
        f.write("[all_vms:children]\n")
```

Add BEFORE this section (after the linux_members:children block):

```python

        # =====================================================================
        # SERVICE GROUPS
        # =====================================================================
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# SERVICE GROUPS (auto-generated from OpenTofu service_hosts)\n")
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# These groups are created from the service_hosts variable in variables.tf.\n")
        f.write("# Use them to target playbooks: ansible-playbook playbooks/setup-web.yml\n")
        f.write("# The playbook automatically runs against hosts in the [web] group.\n\n")

        # Write each service group
        for service in sorted(expanded_services.keys()):
            hosts = expanded_services[service]
            if hosts:  # Only write groups that have hosts
                f.write(f"[{service}]\n")
                for host in sorted(hosts):
                    f.write(f"{host}\n")
                f.write("\n")

```

**Step 2: Verify script syntax**

Run:
```bash
python3 -m py_compile import-tofu-to-ansible.py && echo "Syntax OK"
```

Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add import-tofu-to-ansible.py
git commit -m "feat(inventory): generate service-based Ansible groups

Creates [web], [ssh], [dns], etc. groups from service_hosts mappings.
Enables targeting playbooks by service: --limit web"
```

---

## Task 4: Update Inventory Script - Add host_services Variable

**Files:**
- Modify: `import-tofu-to-ansible.py`

**Step 1: Modify host entry generation to include host_services**

Find the scoring servers section (around line 170):
```python
        for name, floating_ip, internal_ip in zip(scoring_names, scoring_floating_ips, scoring_ips):
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip}\n")
```

Replace with:
```python
        for name, floating_ip, internal_ip in zip(scoring_names, scoring_floating_ips, scoring_ips):
            services = host_to_services.get(name, [])
            services_json = json.dumps(services)
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip} host_services='{services_json}'\n")
```

**Step 2: Apply same pattern to blue_windows section**

Find (around line 182):
```python
        for name, floating_ip, internal_ip in zip(blue_windows_names, blue_windows_floating_ips, blue_windows_ips):
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip}\n")
```

Replace with:
```python
        for name, floating_ip, internal_ip in zip(blue_windows_names, blue_windows_floating_ips, blue_windows_ips):
            services = host_to_services.get(name, [])
            services_json = json.dumps(services)
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip} host_services='{services_json}'\n")
```

**Step 3: Apply same pattern to blue_linux section**

Find (around line 194):
```python
        for name, floating_ip, internal_ip in zip(blue_linux_names, blue_linux_floating_ips, blue_linux_ips):
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip}\n")
```

Replace with:
```python
        for name, floating_ip, internal_ip in zip(blue_linux_names, blue_linux_floating_ips, blue_linux_ips):
            services = host_to_services.get(name, [])
            services_json = json.dumps(services)
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip} host_services='{services_json}'\n")
```

**Step 4: Apply same pattern to red_team section**

Find (around line 206):
```python
        for name, floating_ip, internal_ip in zip(red_kali_names, red_kali_floating_ips, red_kali_ips):
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip}\n")
```

Replace with:
```python
        for name, floating_ip, internal_ip in zip(red_kali_names, red_kali_floating_ips, red_kali_ips):
            services = host_to_services.get(name, [])
            services_json = json.dumps(services)
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip} host_services='{services_json}'\n")
```

**Step 5: Verify script syntax**

Run:
```bash
python3 -m py_compile import-tofu-to-ansible.py && echo "Syntax OK"
```

Expected: `Syntax OK`

**Step 6: Commit**

```bash
git add import-tofu-to-ansible.py
git commit -m "feat(inventory): add host_services variable to each host

Each host now has a JSON list of its assigned services.
Used by scoring template to auto-generate box checks."
```

---

## Task 5: Create scoring_services.yml - Default Check Templates

**Files:**
- Create: `ansible/group_vars/scoring_services.yml`

**Step 1: Create the file**

Create `ansible/group_vars/scoring_services.yml`:

```yaml
---
# ==============================================================================
# SERVICE CHECK DEFAULTS
# ==============================================================================
# This file maps service names to their default scoring engine checks.
# When a host has a service assigned in OpenTofu's service_hosts variable,
# these checks are automatically added to the scoring configuration.
#
# HOW IT WORKS:
# 1. OpenTofu defines: service_hosts = { web = ["webserver"] }
# 2. Inventory script sets: webserver host_services='["ping","ssh","web"]'
# 3. Scoring template looks up each service here to get the check definition
# 4. Result: webserver gets ping, ssh, and web checks in dwayne.conf
#
# TO CUSTOMIZE A CHECK FOR A SPECIFIC HOST:
# Use scoring_overrides.yml instead - it takes priority over these defaults.
#
# TO ADD A NEW SERVICE TYPE:
# 1. Add the service name and check definition below
# 2. Add hosts to service_hosts in opentofu/variables.tf
# 3. Regenerate: tofu apply && python3 import-tofu-to-ansible.py
# ==============================================================================

service_check_defaults:
  # --------------------------------------------------------------------------
  # CONNECTIVITY CHECKS
  # --------------------------------------------------------------------------

  # ICMP ping - basic "is the host alive" check
  ping:
    - type: ping

  # --------------------------------------------------------------------------
  # REMOTE ACCESS - LINUX
  # --------------------------------------------------------------------------

  # SSH - Secure Shell for Linux command-line access
  # Uses linux_users credlist (cyberrange account)
  ssh:
    - type: ssh
      credlists: ["linux_users"]

  # --------------------------------------------------------------------------
  # REMOTE ACCESS - WINDOWS
  # --------------------------------------------------------------------------

  # WinRM - Windows Remote Management for PowerShell access
  # Uses admins credlist (Administrator account)
  winrm:
    - type: winrm
      credlists: ["admins"]

  # RDP - Remote Desktop Protocol for graphical access
  rdp:
    - type: rdp

  # --------------------------------------------------------------------------
  # DIRECTORY SERVICES
  # --------------------------------------------------------------------------

  # DNS - Domain Name System resolution
  # Note: Specific records must be defined in scoring_overrides.yml per-host
  dns:
    - type: dns

  # LDAP - Lightweight Directory Access Protocol
  # Queries Active Directory
  ldap:
    - type: ldap

  # --------------------------------------------------------------------------
  # FILE SERVICES
  # --------------------------------------------------------------------------

  # SMB - Server Message Block (Windows file sharing)
  # Uses TCP check on port 445 for reliability
  smb:
    - type: tcp
      port: 445

  # FTP - File Transfer Protocol
  # Uses linux_users credlist for authenticated access
  ftp:
    - type: ftp
      credlists: ["linux_users"]

  # --------------------------------------------------------------------------
  # APPLICATION SERVICES
  # --------------------------------------------------------------------------

  # Web - HTTP/HTTPS web server
  # Checks root path returns 200 OK
  web:
    - type: web
      urls:
        - path: "/"
          status: 200

  # SQL - MySQL/MariaDB database
  # Checks database exists and is accessible
  sql:
    - type: sql
      credlists: ["linux_users"]
      queries:
        - database: "{{ sql_scoring_db | default('scoring_test') }}"
          databaseexists: true

  # --------------------------------------------------------------------------
  # COMMUNICATION SERVICES
  # --------------------------------------------------------------------------

  # Mail - Email server (SMTP + IMAP)
  # SMTP for sending, IMAP for receiving
  mail:
    - type: smtp
    - type: imap
      credlists: ["domain_users"]

  # IRC - Internet Relay Chat
  # TCP check on default IRC port
  irc:
    - type: tcp
      port: 6667

  # --------------------------------------------------------------------------
  # REMOTE DESKTOP - LINUX
  # --------------------------------------------------------------------------

  # VNC - Virtual Network Computing
  vnc:
    - type: vnc
```

**Step 2: Verify YAML syntax**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/group_vars/scoring_services.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

**Step 3: Commit**

```bash
git add ansible/group_vars/scoring_services.yml
git commit -m "feat(scoring): add service check defaults

Maps service names to their default scoring engine checks.
Used by dwayne.conf.j2 template to auto-generate box configurations."
```

---

## Task 6: Create scoring_overrides.yml - Custom Checks

**Files:**
- Create: `ansible/group_vars/scoring_overrides.yml`

**Step 1: Create the file**

Create `ansible/group_vars/scoring_overrides.yml`:

```yaml
---
# ==============================================================================
# SCORING BOX OVERRIDES
# ==============================================================================
# Use this file to customize auto-generated checks for specific boxes.
#
# TWO TYPES OF CUSTOMIZATION:
#
# 1. OVERRIDE A SERVICE CHECK
#    Define a service key (like "dns" or "web") to completely replace
#    the default check from scoring_services.yml.
#
#    Example - custom DNS records for dc01:
#      dc01:
#        dns:
#          - type: dns
#            records:
#              - kind: "A"
#                domain: "dc01.CDT.local"
#                answer: ["10.10.10.21"]
#
# 2. ADD EXTRA CHECKS
#    Use "extra_checks" to append additional checks (like flag validations)
#    without removing the auto-generated service checks.
#
#    Example - add flag check to webserver:
#      webserver:
#        extra_checks:
#          - type: ssh
#            display: "flag"
#            credlists: ["linux_users"]
#            commands:
#              - command: "cat /var/www/html/flag.txt"
#                contains: true
#                output: "{{ red_team_token }}"
#
# MERGE PRIORITY:
# 1. If override exists for a service -> use override (replaces default)
# 2. If no override -> use default from scoring_services.yml
# 3. extra_checks are always appended after service checks
# ==============================================================================

scoring_box_overrides:
  # --------------------------------------------------------------------------
  # DOMAIN CONTROLLER (dc01)
  # --------------------------------------------------------------------------
  dc01:
    # DNS needs specific records to validate
    dns:
      - type: dns
        records:
          - kind: "A"
            domain: "dc01.CDT.local"
            answer: ["{{ hostvars['dc01']['internal_ip'] }}"]
          - kind: "A"
            domain: "CDT.local"
            answer: ["{{ hostvars['dc01']['internal_ip'] }}"]

    # Flag check - validates Red Team planted flag via WinRM
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
    # Flag check - validates Red Team planted flag via SSH
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
    # Flag check - validates Red Team planted flag via SSH
    extra_checks:
      - type: ssh
        display: "flag"
        credlists: ["linux_users"]
        commands:
          - command: "cat /home/flag.txt 2>/dev/null || echo NOT_FOUND"
            contains: true
            output: "{{ red_team_token }}"
```

**Step 2: Verify YAML syntax**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/group_vars/scoring_overrides.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

**Step 3: Commit**

```bash
git add ansible/group_vars/scoring_overrides.yml
git commit -m "feat(scoring): add per-box override configuration

Allows customizing auto-generated checks for specific boxes.
Supports service overrides and extra_checks (like flag validation)."
```

---

## Task 7: Update scoring.yml - Remove Hardcoded Boxes

**Files:**
- Modify: `ansible/group_vars/scoring.yml`

**Step 1: Remove scoring_boxes section**

Open `ansible/group_vars/scoring.yml` and find the `scoring_boxes:` section (starts around line 196). Delete everything from:

```yaml
scoring_boxes:
  # --------------------------------------------------------------------------
  # DOMAIN CONTROLLER (dc01)
```

To the end of the file (everything after the credlists section).

**Step 2: Add reference comment**

Add at the end of the file (after scoring_credlists):

```yaml

# ==============================================================================
# BOX CONFIGURATIONS
# ==============================================================================
# Box configurations are now AUTO-GENERATED from OpenTofu service_hosts.
#
# HOW IT WORKS:
# 1. Define services in opentofu/variables.tf -> service_hosts
# 2. Run: tofu apply && python3 import-tofu-to-ansible.py
# 3. Inventory sets host_services variable on each host
# 4. dwayne.conf.j2 template generates [[box]] entries automatically
#
# TO CUSTOMIZE CHECKS:
# - Default checks: ansible/group_vars/scoring_services.yml
# - Per-box overrides: ansible/group_vars/scoring_overrides.yml
#
# See docs/plans/2026-01-19-service-mapping-design.md for full documentation.
# ==============================================================================
```

**Step 3: Verify YAML syntax**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/group_vars/scoring.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

**Step 4: Commit**

```bash
git add ansible/group_vars/scoring.yml
git commit -m "refactor(scoring): remove hardcoded scoring_boxes

Box configurations are now auto-generated from service_hosts.
See scoring_services.yml for defaults, scoring_overrides.yml for customizations."
```

---

## Task 8: Update dwayne.conf.j2 Template - Dynamic Box Generation

**Files:**
- Modify: `ansible/roles/scoring_engine/templates/dwayne.conf.j2`

**Step 1: Replace the box generation section**

Find the section starting with:
```jinja2
# ==============================================================================
# BOX CONFIGURATIONS
# ==============================================================================
{% for box in scoring_boxes %}
```

Replace the entire box configuration section (from `# BOX CONFIGURATIONS` to the end of the file) with:

```jinja2
# ==============================================================================
# BOX CONFIGURATIONS (Auto-generated from service_hosts)
# ==============================================================================
# Boxes are generated from OpenTofu service_hosts variable.
# Default checks come from group_vars/scoring_services.yml
# Custom overrides come from group_vars/scoring_overrides.yml
#
# To add a service to a box:
# 1. Edit opentofu/variables.tf -> service_hosts
# 2. Run: tofu apply && python3 import-tofu-to-ansible.py
# 3. Run: ansible-playbook playbooks/setup-scoring-engine.yml

{% set scored_hosts = [] %}
{% for host in groups['blue_team'] | default([]) %}
{% if hostvars[host]['host_services'] is defined %}
{% set _ = scored_hosts.append(host) %}
{% endif %}
{% endfor %}

{% for hostname in scored_hosts %}
{% set host_services = hostvars[hostname]['host_services'] | from_json if hostvars[hostname]['host_services'] is string else hostvars[hostname]['host_services'] %}
{% set box_overrides = scoring_box_overrides.get(hostname, {}) if scoring_box_overrides is defined else {} %}
[[box]]
name = "{{ hostname }}"
ip = "{{ hostvars[hostname]['internal_ip'] }}"

{% for service in host_services %}
{% if service in box_overrides %}
{# Use override checks for this service #}
{% for check in box_overrides[service] %}
    [[box.{{ check.type }}]]
{% if check.display is defined %}
    display = "{{ check.display }}"
{% endif %}
{% if check.credlists is defined %}
    credlists = [{% for cl in check.credlists %}"{{ cl }}"{% if not loop.last %}, {% endif %}{% endfor %}]
{% endif %}
{% if check.port is defined %}
    port = {{ check.port }}
{% endif %}
{% if check.encrypted is defined %}
    encrypted = {{ check.encrypted | lower }}
{% endif %}
{% if check.anonymous is defined %}
    anonymous = {{ check.anonymous | lower }}
{% endif %}
{% if check.records is defined %}
{% for record in check.records %}
        [[box.dns.record]]
        kind = "{{ record.kind }}"
        domain = "{{ record.domain }}"
        answer = [{% for ans in record.answer %}"{{ ans }}"{% if not loop.last %}, {% endif %}{% endfor %}]

{% endfor %}
{% endif %}
{% if check.urls is defined %}
{% for url in check.urls %}
        [[box.web.url]]
{% if url.path is defined %}
        path = "{{ url.path }}"
{% endif %}
{% if url.status is defined %}
        status = {{ url.status }}
{% endif %}
{% if url.regex is defined %}
        regex = "{{ url.regex }}"
{% endif %}

{% endfor %}
{% endif %}
{% if check.commands is defined %}
{% for cmd in check.commands %}
        [[box.{{ check.type }}.command]]
        command = '{{ cmd.command }}'
{% if cmd.output is defined %}
        output = "{{ cmd.output }}"
{% endif %}
{% if cmd.contains is defined %}
        contains = {{ cmd.contains | lower }}
{% endif %}
{% if cmd.useregex is defined %}
        useregex = {{ cmd.useregex | lower }}
{% endif %}

{% endfor %}
{% endif %}
{% if check.queries is defined %}
{% for query in check.queries %}
        [[box.sql.query]]
{% if query.database is defined %}
        database = "{{ query.database }}"
{% endif %}
{% if query.table is defined %}
        table = "{{ query.table }}"
{% endif %}
{% if query.column is defined %}
        column = "{{ query.column }}"
{% endif %}
{% if query.output is defined %}
        output = "{{ query.output }}"
{% endif %}
{% if query.contains is defined %}
        contains = {{ query.contains | lower }}
{% endif %}
{% if query.databaseexists is defined %}
        databaseexists = {{ query.databaseexists | lower }}
{% endif %}

{% endfor %}
{% endif %}
{% if check.domain is defined %}
    domain = "{{ check.domain }}"
{% endif %}
{% if check.share is defined %}
    share = "{{ check.share }}"
{% endif %}
{% if check.files is defined %}
{% for file in check.files %}
        [[box.{{ check.type }}.file]]
        name = '{{ file.name }}'
{% if file.hash is defined %}
        hash = "{{ file.hash }}"
{% endif %}
{% if file.regex is defined %}
        regex = "{{ file.regex }}"
{% endif %}

{% endfor %}
{% endif %}

{% endfor %}
{% elif service_check_defaults is defined and service in service_check_defaults %}
{# Use default checks for this service #}
{% for check in service_check_defaults[service] %}
    [[box.{{ check.type }}]]
{% if check.display is defined %}
    display = "{{ check.display }}"
{% endif %}
{% if check.credlists is defined %}
    credlists = [{% for cl in check.credlists %}"{{ cl }}"{% if not loop.last %}, {% endif %}{% endfor %}]
{% endif %}
{% if check.port is defined %}
    port = {{ check.port }}
{% endif %}
{% if check.encrypted is defined %}
    encrypted = {{ check.encrypted | lower }}
{% endif %}
{% if check.anonymous is defined %}
    anonymous = {{ check.anonymous | lower }}
{% endif %}
{% if check.urls is defined %}
{% for url in check.urls %}
        [[box.web.url]]
{% if url.path is defined %}
        path = "{{ url.path }}"
{% endif %}
{% if url.status is defined %}
        status = {{ url.status }}
{% endif %}
{% if url.regex is defined %}
        regex = "{{ url.regex }}"
{% endif %}

{% endfor %}
{% endif %}
{% if check.queries is defined %}
{% for query in check.queries %}
        [[box.sql.query]]
{% if query.database is defined %}
        database = "{{ query.database }}"
{% endif %}
{% if query.databaseexists is defined %}
        databaseexists = {{ query.databaseexists | lower }}
{% endif %}

{% endfor %}
{% endif %}

{% endfor %}
{% endif %}
{% endfor %}
{# Append extra_checks if defined #}
{% if box_overrides.extra_checks is defined %}
{% for check in box_overrides.extra_checks %}
    [[box.{{ check.type }}]]
{% if check.display is defined %}
    display = "{{ check.display }}"
{% endif %}
{% if check.credlists is defined %}
    credlists = [{% for cl in check.credlists %}"{{ cl }}"{% if not loop.last %}, {% endif %}{% endfor %}]
{% endif %}
{% if check.port is defined %}
    port = {{ check.port }}
{% endif %}
{% if check.commands is defined %}
{% for cmd in check.commands %}
        [[box.{{ check.type }}.command]]
        command = '{{ cmd.command }}'
{% if cmd.output is defined %}
        output = "{{ cmd.output }}"
{% endif %}
{% if cmd.contains is defined %}
        contains = {{ cmd.contains | lower }}
{% endif %}
{% if cmd.useregex is defined %}
        useregex = {{ cmd.useregex | lower }}
{% endif %}

{% endfor %}
{% endif %}

{% endfor %}
{% endif %}
{% endfor %}
```

**Step 2: Verify Jinja2 syntax**

Run:
```bash
python3 -c "from jinja2 import Template; Template(open('ansible/roles/scoring_engine/templates/dwayne.conf.j2').read())" && echo "Jinja2 OK"
```

Expected: `Jinja2 OK`

**Step 3: Commit**

```bash
git add ansible/roles/scoring_engine/templates/dwayne.conf.j2
git commit -m "feat(scoring): auto-generate box configs from service_hosts

Template now iterates hosts with host_services variable and generates
[[box]] entries using defaults from scoring_services.yml with overrides
from scoring_overrides.yml."
```

---

## Task 9: Create User Documentation

**Files:**
- Create: `docs/service-configuration.md`

**Step 1: Create comprehensive user guide**

Create `docs/service-configuration.md`:

```markdown
# Service Configuration Guide

This guide explains how to configure which services run on which boxes in your CTF infrastructure.

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
```

**Step 2: Verify markdown renders**

Run:
```bash
head -50 docs/service-configuration.md
```

Expected: Clean markdown output

**Step 3: Commit**

```bash
git add docs/service-configuration.md
git commit -m "docs: add comprehensive service configuration guide

Student-friendly documentation covering:
- Quick start workflow
- How the system works (data flow)
- Adding/customizing services
- Supported services reference
- Troubleshooting guide"
```

---

## Task 10: Final Integration Test

**Step 1: Run linting**

```bash
./check.sh
```

Expected: OpenTofu passes, Ansible may have pre-existing warnings

**Step 2: Verify all files are committed**

```bash
git status
```

Expected: Clean working tree (nothing to commit)

**Step 3: Review commit history**

```bash
git log --oneline -10
```

Expected: See all feature commits in order

**Step 4: Create summary commit (optional)**

If there are any uncommitted changes:

```bash
git add -A
git commit -m "chore: finalize service mapping implementation"
```

---

## Completion Checklist

- [ ] Task 1: service_hosts variable in OpenTofu
- [ ] Task 2: Inventory script parses services
- [ ] Task 3: Inventory script generates service groups
- [ ] Task 4: Inventory script adds host_services variable
- [ ] Task 5: scoring_services.yml with default checks
- [ ] Task 6: scoring_overrides.yml for customizations
- [ ] Task 7: scoring.yml cleaned up (no hardcoded boxes)
- [ ] Task 8: dwayne.conf.j2 dynamic generation
- [ ] Task 9: User documentation
- [ ] Task 10: Final integration test
