# DWAYNE-INATOR-5000 Scoring Engine Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy the DWAYNE-INATOR-5000 scoring engine on the Grey Team scoring server using Ansible.

**Architecture:** Ansible role installs Go, builds the scoring engine from submodule source, generates TOML config from YAML variables, and runs as a systemd service.

**Tech Stack:** Ansible, Go 1.20+, systemd, TOML config, Jinja2 templates

## Documentation Guidelines

**Target Audience:** Students who have:
- Never used Ansible before
- Never used a scoring engine
- Never competed in or organized a CTF/CCDC competition

**Writing Style:**
- Explain every concept when first introduced
- Add "WHY" comments, not just "WHAT" comments
- Include links to relevant documentation
- Use analogies to explain complex concepts
- Assume nothing about prior knowledge
- Explain acronyms (CCDC, CTF, SLA, etc.)

---

## Task 1: Create Scoring Configuration Variables

**Files:**
- Create: `ansible/group_vars/scoring.yml`

**Step 1: Create the centralized scoring configuration file**

```yaml
---
# ==============================================================================
# SCORING ENGINE CONFIGURATION
# ==============================================================================
# This file configures the DWAYNE-INATOR-5000 scoring engine for your competition.
#
# WHAT IS A SCORING ENGINE?
# In Capture The Flag (CTF) and Collegiate Cyber Defense Competition (CCDC)
# style events, a scoring engine automatically checks if services (like websites,
# email servers, etc.) are running correctly. Teams earn points when their
# services are up and working, and lose points when services go down.
#
# COMPETITION ROLES:
# - Grey Team: Runs the competition infrastructure (that's you!)
# - Blue Team: Defenders who keep services running and secure
# - Red Team: Attackers who try to break into Blue Team systems
#
# HOW TO USE THIS FILE:
# 1. Edit the settings below to match your competition
# 2. Run: ansible-playbook playbooks/setup-scoring-engine.yml
# 3. Access the web scoreboard at http://<scoring-server-ip>:8080
#
# ANSIBLE VARIABLES EXPLAINED:
# Variables defined here (like scoring_event_name) are automatically
# available in playbooks and templates. Ansible loads all .yml files
# from group_vars/ based on which hosts are being configured.
#
# DOCUMENTATION:
# - Ansible Variables: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html
# - DWAYNE-INATOR-5000: https://github.com/DSU-DefSec/DWAYNE-INATOR-5000
# ==============================================================================

# ------------------------------------------------------------------------------
# EVENT SETTINGS
# ------------------------------------------------------------------------------
# Basic information about your competition.

# The name shown on the scoreboard
scoring_event_name: "CDT Attack/Defend Competition"

# Timezone for timestamps on the scoreboard
# Find yours at: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
scoring_timezone: "America/New_York"

# Start with scoring paused? (true = paused, false = running immediately)
# TIP: Set to true so you can verify everything works before starting the clock
scoring_start_paused: true

# Show detailed information to competitors on the scoreboard
scoring_verbose: true

# Web interface port (default: 8080)
# Access scoreboard at: http://<server-ip>:8080
scoring_port: 8080

# ------------------------------------------------------------------------------
# TIMING SETTINGS
# ------------------------------------------------------------------------------
# Control how often services are checked and how points are calculated.
#
# EXAMPLE SCENARIO:
# With delay=60 and timeout=10, the engine checks each service every ~60 seconds.
# If a service doesn't respond within 10 seconds, that check fails.
# After 5 failed checks (sla_threshold), the team gets an SLA violation penalty.

# Seconds between service checks (how often to test each service)
scoring_delay: 60

# Random variation added to delay (prevents predictable check timing)
# This stops teams from "gaming" the system by only having services up during checks
scoring_jitter: 5

# How long to wait for a service to respond before marking it as down
scoring_timeout: 10

# Points awarded for each successful service check
scoring_service_points: 10

# SLA = Service Level Agreement
# How many consecutive failed checks before triggering an SLA violation
# Think of it like "three strikes and you're out" but for service uptime
scoring_sla_threshold: 5

# Penalty points deducted for an SLA violation
scoring_sla_points: 10

# ------------------------------------------------------------------------------
# ADMIN ACCOUNTS
# ------------------------------------------------------------------------------
# Admin users can:
# - View all team scores and detailed logs
# - Start/pause/reset the competition
# - Grade inject submissions (manual challenges)
#
# SECURITY NOTE: Change these passwords for real competitions!
# These are just defaults for lab/training use.

scoring_admins:
  - name: admin
    password: "ScoringAdmin123!"

# ------------------------------------------------------------------------------
# TEAMS
# ------------------------------------------------------------------------------
# Define the teams competing in your event.
#
# SINGLE TEAM MODE (this config):
# One Blue Team defends all the boxes. Good for training and practice.
#
# MULTI-TEAM MODE (advanced):
# Multiple Blue Teams each defend their own copy of the infrastructure.
# Requires separate network ranges per team (e.g., Team1: 10.10.1.x, Team2: 10.10.2.x)
#
# The 'id' field identifies the team. In multi-team setups, this replaces
# the 'x' in IP addresses (e.g., 10.10.x.21 becomes 10.10.1.21 for team "1")

scoring_teams:
  - id: "1"
    password: "BlueTeam123!"   # Teams use this to log in and change service passwords

# ------------------------------------------------------------------------------
# CREDENTIAL LISTS
# ------------------------------------------------------------------------------
# Define username/password combinations that the scoring engine uses to
# test services. These simulate real users trying to access services.
#
# WHY CREDENTIAL LISTS?
# The scoring engine needs to log into services (SSH, Windows, databases)
# to verify they're working. These credentials must match what's actually
# configured on the target systems.
#
# IMPORTANT FOR BLUE TEAMS:
# - Teams CAN change passwords during competition (to lock out attackers)
# - Teams CANNOT add new users or change usernames
# - When a team changes a password, they update it in the scoring web interface
#
# MULTIPLE LISTS:
# Different services may use different accounts. For example:
# - "domain_users" for regular user logins
# - "admins" for administrative access
# - "linux_users" for Linux-specific accounts

scoring_credlists:
  # Regular domain users (these are created by the create-domain-users.yml playbook)
  - name: "domain_users"
    usernames:
      - jdoe
      - asmith
      - bwilson
      - mjohnson
      - dlee
    default_password: "UserPass123!"

  # Windows Administrator account
  - name: "admins"
    usernames:
      - Administrator
    default_password: "Cyberrange123!"

  # Linux local user account (created by cloud-init during VM deployment)
  - name: "linux_users"
    usernames:
      - cyberrange
    default_password: "Cyberrange123!"

# ------------------------------------------------------------------------------
# BOX DEFINITIONS WITH CHECKS
# ------------------------------------------------------------------------------
# A "box" is a server/computer that the scoring engine monitors.
# Each box has one or more "checks" that test if specific services are working.
#
# SUPPORTED CHECK TYPES:
# - ping:  Can we reach the server? (ICMP)
# - ssh:   Can we log into Linux via SSH?
# - winrm: Can we remotely manage Windows? (Windows Remote Management)
# - rdp:   Is Remote Desktop available?
# - smb:   Can we access Windows file shares?
# - dns:   Does the DNS server resolve names correctly?
# - web:   Is the website responding?
# - ftp:   Can we access FTP file transfers?
# - sql:   Can we query the database?
# - ldap:  Can we query the directory service?
# - smtp:  Can we send email?
# - imap:  Can we receive email?
# - tcp:   Is a specific port open?
# - vnc:   Is VNC remote desktop available?
#
# ANATOMY OF A CHECK:
#   - type: ssh                    # What kind of service to test
#     credlists: ["linux_users"]   # Which credentials to use (defined above)
#     port: 22                     # Optional: non-standard port
#
# DOCUMENTATION:
# - Full check options: https://github.com/DSU-DefSec/DWAYNE-INATOR-5000#configuration

scoring_boxes:
  # --------------------------------------------------------------------------
  # DOMAIN CONTROLLER (dc01)
  # --------------------------------------------------------------------------
  # The Domain Controller is the "brain" of a Windows network. It handles:
  # - User authentication (Active Directory)
  # - DNS (translating names like "dc01.CDT.local" to IP addresses)
  # - Group policies and permissions
  #
  # If the DC goes down, users can't log in and the whole network suffers.
  # This makes it a high-value target for attackers AND a critical service
  # for defenders to protect.
  - name: "dc01"
    ip: "10.10.10.21"
    checks:
      # Basic connectivity - can we reach the server at all?
      - type: ping

      # Windows Remote Management - can we run commands remotely?
      # Used by administrators (and attackers!) to manage Windows servers
      - type: winrm
        credlists: ["admins"]

      # Remote Desktop Protocol - can users connect with a graphical interface?
      - type: rdp

      # Server Message Block - Windows file sharing
      # Tests if shared folders are accessible
      - type: smb
        credlists: ["admins"]

      # Domain Name System - does name resolution work?
      # This check asks "what is the IP address of dc01.CDT.local?"
      # and verifies the answer is correct
      - type: dns
        records:
          - kind: "A"                    # A = Address record (name -> IP)
            domain: "dc01.CDT.local"     # The name to look up
            answer: ["10.10.10.21"]      # Expected IP address(es)

  # --------------------------------------------------------------------------
  # WINDOWS MEMBER SERVER (blue-win-2)
  # --------------------------------------------------------------------------
  # A "member server" is a Windows server that's joined to the domain
  # but isn't a Domain Controller. It might run applications, databases,
  # file shares, or other services.
  - name: "blue-win-2"
    ip: "10.10.10.22"
    checks:
      - type: ping
      - type: winrm
        credlists: ["admins"]
      - type: rdp

  # --------------------------------------------------------------------------
  # LINUX WEB SERVER (webserver)
  # --------------------------------------------------------------------------
  # This Linux server hosts a website. Web servers are common targets
  # because they're exposed to the network and often have vulnerabilities.
  - name: "webserver"
    ip: "10.10.10.31"
    checks:
      - type: ping

      # Secure Shell - remote command-line access to Linux
      - type: ssh
        credlists: ["linux_users"]

      # Web check - is the website responding?
      - type: web
        urls:
          - path: "/"           # Check the homepage
            status: 200         # HTTP 200 = "OK" (page loaded successfully)

  # --------------------------------------------------------------------------
  # ADDITIONAL LINUX SERVER (blue-linux-2)
  # --------------------------------------------------------------------------
  # Another Linux server for the Blue Team to defend.
  # Could host databases, applications, or other services.
  - name: "blue-linux-2"
    ip: "10.10.10.32"
    checks:
      - type: ping
      - type: ssh
        credlists: ["linux_users"]
```

**Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('ansible/group_vars/scoring.yml'))"`
Expected: No output (success)

**Step 3: Commit**

```bash
git add ansible/group_vars/scoring.yml
git commit -m "feat(scoring): add centralized scoring configuration

Define event settings, timing, teams, credentials, and box checks
for DWAYNE-INATOR-5000 scoring engine."
```

---

## Task 2: Create Role Directory Structure

**Files:**
- Create: `ansible/roles/scoring_engine/tasks/main.yml`
- Create: `ansible/roles/scoring_engine/defaults/main.yml`
- Create: `ansible/roles/scoring_engine/handlers/main.yml`
- Create: `ansible/roles/scoring_engine/templates/` (directory)

**Step 1: Create role directories**

Run: `mkdir -p ansible/roles/scoring_engine/{tasks,defaults,handlers,templates}`

**Step 2: Create defaults file**

```yaml
---
# ==============================================================================
# SCORING ENGINE ROLE - DEFAULT VARIABLES
# ==============================================================================
# This file defines default values for variables used by this Ansible role.
#
# WHAT ARE ROLE DEFAULTS?
# When Ansible runs a role, it looks for variables in several places:
# 1. defaults/main.yml (this file) - lowest priority, easily overridden
# 2. vars/main.yml - higher priority, harder to override
# 3. group_vars/ - variables for groups of hosts
# 4. host_vars/ - variables for specific hosts
# 5. Command line (-e flag) - highest priority
#
# WHY USE DEFAULTS?
# Defaults provide sensible starting values so the role works "out of the box"
# but can be customized by setting variables in group_vars/scoring.yml
#
# DOCUMENTATION:
# - Ansible Variable Precedence: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable
# - Ansible Roles: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html
# ==============================================================================

# ------------------------------------------------------------------------------
# INSTALLATION PATHS
# ------------------------------------------------------------------------------
# Where to install the scoring engine on the server

# Directory where scoring engine files are installed
# /opt is the standard location for optional/add-on software on Linux
scoring_install_dir: /opt/scoring-engine

# Name of the compiled binary (the actual program that runs)
scoring_binary_name: dwayne-inator

# ------------------------------------------------------------------------------
# GO BUILD SETTINGS
# ------------------------------------------------------------------------------
# The scoring engine is written in Go and must be compiled before running

# Additional flags to pass to 'go build' command
# Leave empty for default build, or add flags like "-ldflags '-s -w'" to reduce binary size
scoring_go_build_flags: ""

# ------------------------------------------------------------------------------
# SERVICE SETTINGS
# ------------------------------------------------------------------------------
# Configure how the scoring engine runs as a system service

# Name of the systemd service (used with systemctl commands)
# Example: systemctl status dwayne-inator
scoring_service_name: dwayne-inator

# Which Linux user runs the service
# Using root for simplicity, but could be a dedicated service account for security
scoring_service_user: root

# ------------------------------------------------------------------------------
# DEFAULT SCORING SETTINGS
# ------------------------------------------------------------------------------
# These provide fallback values if not specified in group_vars/scoring.yml
# In practice, you should always define these in group_vars/scoring.yml

scoring_event_name: "Competition"
scoring_timezone: "America/New_York"
scoring_start_paused: true
scoring_verbose: true
scoring_port: 8080
scoring_delay: 60
scoring_jitter: 5
scoring_timeout: 10
scoring_service_points: 10
scoring_sla_threshold: 5
scoring_sla_points: 10
```

**Step 3: Create handlers file**

```yaml
---
# ==============================================================================
# SCORING ENGINE ROLE - HANDLERS
# ==============================================================================
# Handlers are special tasks that only run when "notified" by other tasks.
#
# WHY USE HANDLERS?
# Imagine you change a configuration file. You need to restart the service
# for changes to take effect. But what if multiple tasks change config files?
# You don't want to restart after EVERY change - that's wasteful and slow.
#
# Handlers solve this: tasks "notify" a handler when they make changes,
# and Ansible runs each handler ONCE at the end, no matter how many times
# it was notified.
#
# EXAMPLE FLOW:
# 1. Task "Deploy config file" changes dwayne.conf -> notifies "restart scoring engine"
# 2. Task "Deploy service file" changes the .service file -> notifies "restart scoring engine"
# 3. All tasks complete
# 4. Handler "restart scoring engine" runs ONCE (not twice!)
#
# DOCUMENTATION:
# - Ansible Handlers: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html
# ==============================================================================

# Restart the scoring engine service
# Called when configuration or service files change
- name: restart scoring engine
  ansible.builtin.systemd:
    name: "{{ scoring_service_name }}"
    state: restarted
    daemon_reload: true  # Also reload systemd to pick up service file changes

# Reload systemd configuration without restarting services
# Called when only the .service file changes but we want to defer restart
- name: reload systemd
  ansible.builtin.systemd:
    daemon_reload: true
```

**Step 4: Create placeholder tasks file**

```yaml
---
# ==============================================================================
# SCORING ENGINE ROLE - TASKS
# ==============================================================================
# Placeholder - will be implemented in next tasks

- name: Placeholder task
  ansible.builtin.debug:
    msg: "Scoring engine role tasks will be implemented"
```

**Step 5: Commit**

```bash
git add ansible/roles/scoring_engine/
git commit -m "feat(scoring): create scoring_engine role structure

Add defaults, handlers, and placeholder tasks for the role."
```

---

## Task 3: Implement Role Tasks - Dependencies and Build

**Files:**
- Modify: `ansible/roles/scoring_engine/tasks/main.yml`

**Step 1: Replace placeholder with dependency installation tasks**

```yaml
---
# ==============================================================================
# SCORING ENGINE ROLE - TASKS
# ==============================================================================
# This file contains all the steps Ansible performs to install and configure
# the DWAYNE-INATOR-5000 scoring engine.
#
# WHAT ARE ANSIBLE TASKS?
# Tasks are individual actions Ansible performs on target servers. They run
# in order from top to bottom. Each task uses a "module" (like apt, copy, file)
# to perform a specific action.
#
# TASK STRUCTURE:
#   - name: Human-readable description (shows in output)
#     ansible.builtin.module_name:    # Which module to use
#       parameter1: value1            # Module-specific options
#       parameter2: value2
#     register: result_variable       # Save output to a variable (optional)
#     when: condition                 # Only run if condition is true (optional)
#     notify: handler_name            # Trigger a handler when task changes something
#
# WHAT THIS ROLE DOES (in order):
# 1. Installs Go programming language and build tools (gcc, git)
# 2. Creates a directory for the scoring engine
# 3. Copies the scoring engine source code from this repo to the server
# 4. Compiles (builds) the Go code into an executable program
# 5. Generates the configuration file from your settings
# 6. Sets up a systemd service so it runs automatically
# 7. Starts the service and verifies it's working
#
# DOCUMENTATION:
# - Ansible Tasks: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html
# - Module Index: https://docs.ansible.com/ansible/latest/collections/index_module.html
# ==============================================================================

# ------------------------------------------------------------------------------
# STEP 1: Install Build Dependencies
# ------------------------------------------------------------------------------
# The scoring engine is written in Go, so we need the Go compiler.
# It also uses go-sqlite3 which requires gcc (a C compiler) to build.

- name: Install build dependencies
  ansible.builtin.apt:
    # APT MODULE: Installs packages on Debian/Ubuntu systems
    # Similar to running: sudo apt install golang-go gcc git
    # Docs: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html
    name:
      - golang-go    # Go programming language compiler
      - gcc          # C compiler (required for go-sqlite3)
      - git          # Version control (used during Go builds)
    state: present       # Ensure packages are installed (vs. absent to remove)
    update_cache: true   # Run 'apt update' first to refresh package lists
  register: deps_install
  # REGISTER: Saves the task's output to a variable (deps_install)
  # We can check deps_install.changed to see if anything was installed

- name: Display Go version
  ansible.builtin.command: go version
  # COMMAND MODULE: Runs shell commands
  # Docs: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/command_module.html
  register: go_version
  changed_when: false
  # CHANGED_WHEN: Tells Ansible when to consider this task as having "changed" something
  # 'false' means this task never reports a change (it's just checking, not modifying)

- name: Show Go version
  ansible.builtin.debug:
    # DEBUG MODULE: Prints messages during playbook execution
    # Useful for showing variable values or status information
    # Docs: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/debug_module.html
    msg: "{{ go_version.stdout }}"
    # {{ variable }} is Jinja2 syntax - Ansible replaces it with the variable's value

# ------------------------------------------------------------------------------
# STEP 2: Create Installation Directory
# ------------------------------------------------------------------------------
# Create a dedicated directory for the scoring engine files

- name: Create scoring engine directory
  ansible.builtin.file:
    # FILE MODULE: Manages files and directories
    # Docs: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html
    path: "{{ scoring_install_dir }}"    # Directory path (default: /opt/scoring-engine)
    state: directory                      # Create a directory (vs. file, link, absent)
    owner: "{{ scoring_service_user }}"   # Who owns the directory
    mode: "0755"                          # Permissions: rwxr-xr-x (owner can write, others can read/execute)

# ------------------------------------------------------------------------------
# STEP 3: Copy Scoring Engine Source
# ------------------------------------------------------------------------------
# Copy the scoring engine code from this repository to the target server
# The source is in the git submodule at scoring/DWAYNE-INATOR-5000/

- name: Copy DWAYNE-INATOR-5000 source
  ansible.builtin.copy:
    # COPY MODULE: Copies files from the control machine to target servers
    # Docs: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html
    src: "{{ playbook_dir }}/../scoring/DWAYNE-INATOR-5000/"
    # playbook_dir is a magic variable = directory containing the playbook
    # So this resolves to: ansible/playbooks/../scoring/DWAYNE-INATOR-5000/
    # Which simplifies to: scoring/DWAYNE-INATOR-5000/
    dest: "{{ scoring_install_dir }}/"
    owner: "{{ scoring_service_user }}"
    mode: preserve    # Keep original file permissions
  register: source_copy
  # We register this so we can check if files changed and trigger a rebuild

# ------------------------------------------------------------------------------
# STEP 4: Build Scoring Engine
# ------------------------------------------------------------------------------
# Compile the Go source code into an executable binary
# This is like running: cd /opt/scoring-engine && go build -o dwayne-inator

- name: Build scoring engine binary
  ansible.builtin.command:
    cmd: go build {{ scoring_go_build_flags }} -o {{ scoring_binary_name }}
    chdir: "{{ scoring_install_dir }}"    # Change to this directory before running
    creates: "{{ scoring_install_dir }}/{{ scoring_binary_name }}"
    # CREATES: Only run this task if the specified file DOESN'T exist
    # This makes the task idempotent (safe to run multiple times)
    # First run: binary doesn't exist -> task runs
    # Second run: binary exists -> task skips (saves time!)
  environment:
    # ENVIRONMENT: Set environment variables for this command
    # Go uses these to cache downloaded packages and compiled code
    GOCACHE: "{{ scoring_install_dir }}/.cache/go-build"
    GOPATH: "{{ scoring_install_dir }}/.cache/go"
  register: build_result

- name: Rebuild if source changed
  ansible.builtin.command:
    cmd: go build {{ scoring_go_build_flags }} -o {{ scoring_binary_name }}
    chdir: "{{ scoring_install_dir }}"
  environment:
    GOCACHE: "{{ scoring_install_dir }}/.cache/go-build"
    GOPATH: "{{ scoring_install_dir }}/.cache/go"
  when: source_copy.changed
  # WHEN: Conditional execution - only run this task if condition is true
  # source_copy.changed is true if the copy task actually changed files
  # This ensures we rebuild when the code updates
  notify: restart scoring engine
  # NOTIFY: Trigger the "restart scoring engine" handler
  # Handler won't run immediately - it runs after all tasks complete

# ------------------------------------------------------------------------------
# STEP 5: Deploy Configuration
# ------------------------------------------------------------------------------
# Generate the dwayne.conf configuration file from our YAML variables
# The template transforms group_vars/scoring.yml into TOML format

- name: Deploy scoring engine configuration
  ansible.builtin.template:
    # TEMPLATE MODULE: Process Jinja2 templates and copy to target
    # Unlike 'copy', this evaluates {{ variables }} and {% logic %}
    # Docs: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html
    src: dwayne.conf.j2          # Template file (in role's templates/ directory)
    dest: "{{ scoring_install_dir }}/dwayne.conf"
    owner: "{{ scoring_service_user }}"
    mode: "0640"    # rw-r----- (owner read/write, group read, others nothing)
                    # More restrictive because config may contain passwords
  notify: restart scoring engine

# ------------------------------------------------------------------------------
# STEP 6: Deploy Systemd Service
# ------------------------------------------------------------------------------
# Create a systemd service so the scoring engine:
# - Starts automatically when the server boots
# - Restarts automatically if it crashes
# - Can be controlled with systemctl commands

- name: Deploy systemd service unit
  ansible.builtin.template:
    src: dwayne.service.j2
    dest: /etc/systemd/system/{{ scoring_service_name }}.service
    # /etc/systemd/system/ is where custom services go
    owner: root
    mode: "0644"
  notify:
    # You can notify multiple handlers!
    - reload systemd       # Tell systemd to re-read service files
    - restart scoring engine

# ------------------------------------------------------------------------------
# STEP 7: Enable and Start Service
# ------------------------------------------------------------------------------
# Enable = start on boot, Started = start right now

- name: Enable and start scoring engine service
  ansible.builtin.systemd:
    # SYSTEMD MODULE: Manage systemd services
    # Docs: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/systemd_module.html
    name: "{{ scoring_service_name }}"
    enabled: true      # Start on boot (like: systemctl enable dwayne-inator)
    state: started     # Start now (like: systemctl start dwayne-inator)
    daemon_reload: true  # Reload systemd config first (in case service file changed)

# ------------------------------------------------------------------------------
# STEP 8: Verify Service is Running
# ------------------------------------------------------------------------------
# Make sure the scoring engine actually started and is accepting connections

- name: Wait for scoring engine to start
  ansible.builtin.wait_for:
    # WAIT_FOR MODULE: Wait for a condition before continuing
    # Docs: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/wait_for_module.html
    port: "{{ scoring_port }}"   # Wait for this port to be open
    host: 127.0.0.1              # Check localhost (we're on the scoring server)
    delay: 5                     # Wait 5 seconds before first check
    timeout: 60                  # Fail if not ready within 60 seconds

- name: Display service status
  ansible.builtin.command: systemctl status {{ scoring_service_name }}
  register: service_status
  changed_when: false

- name: Show service status
  ansible.builtin.debug:
    msg: "{{ service_status.stdout_lines }}"
    # stdout_lines splits the output into a list (one item per line)
    # This makes it display nicely in Ansible's output
```

**Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('ansible/roles/scoring_engine/tasks/main.yml'))"`
Expected: No output (success)

**Step 3: Commit**

```bash
git add ansible/roles/scoring_engine/tasks/main.yml
git commit -m "feat(scoring): implement role tasks for install and build

Add tasks for dependency installation, source copying, Go build,
configuration deployment, and systemd service management."
```

---

## Task 4: Create Systemd Service Template

**Files:**
- Create: `ansible/roles/scoring_engine/templates/dwayne.service.j2`

**Step 1: Create the systemd service template**

```ini
# {{ ansible_managed }}
# ==============================================================================
# SYSTEMD SERVICE UNIT FOR DWAYNE-INATOR-5000 SCORING ENGINE
# ==============================================================================
# This file tells systemd (Linux's service manager) how to run the scoring engine.
#
# WHAT IS SYSTEMD?
# Systemd is the system and service manager for most modern Linux distributions.
# It handles starting services at boot, managing dependencies, and restarting
# crashed services. Think of it as the "control center" for background processes.
#
# SERVICE UNIT FILES:
# Files like this one (ending in .service) define how to run a program as a
# service. They go in /etc/systemd/system/ for custom services.
#
# USEFUL COMMANDS:
#   systemctl start dwayne-inator    # Start the service
#   systemctl stop dwayne-inator     # Stop the service
#   systemctl restart dwayne-inator  # Restart the service
#   systemctl status dwayne-inator   # Check if it's running
#   systemctl enable dwayne-inator   # Start automatically on boot
#   journalctl -fu dwayne-inator     # View logs (f=follow, u=unit)
#
# JINJA2 TEMPLATE:
# This is a Jinja2 template (notice the .j2 extension). Ansible replaces
# {{ variable }} with actual values before copying to the server.
#
# DOCUMENTATION:
# - Systemd Service Units: https://www.freedesktop.org/software/systemd/man/systemd.service.html
# - Jinja2 Templates: https://jinja.palletsprojects.com/
# ==============================================================================

# ------------------------------------------------------------------------------
# [Unit] Section - Metadata and Dependencies
# ------------------------------------------------------------------------------
# Describes the service and when it should start

[Unit]
# Human-readable description (shown in systemctl status output)
Description=DWAYNE-INATOR-5000 Scoring Engine

# Link to documentation for administrators
Documentation=https://github.com/DSU-DefSec/DWAYNE-INATOR-5000

# Start this service AFTER the network is available
# (The scoring engine needs network access to check services)
After=network.target

# ------------------------------------------------------------------------------
# [Service] Section - How to Run the Program
# ------------------------------------------------------------------------------
# Defines the actual command and runtime behavior

[Service]
# Type=simple means: the process started by ExecStart IS the service
# (as opposed to Type=forking where it forks into background)
Type=simple

# Which Linux user runs this service
# Using root for simplicity, but production systems might use a dedicated user
User={{ scoring_service_user }}

# Working directory - where the service runs from
# Important because the scoring engine looks for dwayne.conf here
WorkingDirectory={{ scoring_install_dir }}

# The actual command to start the scoring engine
ExecStart={{ scoring_install_dir }}/{{ scoring_binary_name }}

# Restart policy: restart if the process crashes (exits with error)
# Alternatives: always, no, on-success, on-abort
Restart=on-failure

# Wait 5 seconds before restarting (prevents rapid restart loops)
RestartSec=5

# ------------------------------------------------------------------------------
# Logging Configuration
# ------------------------------------------------------------------------------
# Send all output to systemd's journal (viewable with journalctl)

StandardOutput=journal
StandardError=journal

# Identifier used in log entries (defaults to service name)
SyslogIdentifier={{ scoring_service_name }}

# ------------------------------------------------------------------------------
# Security Hardening
# ------------------------------------------------------------------------------
# These options limit what the service can do, reducing damage if compromised

# Prevent the service from gaining new privileges
NoNewPrivileges=true

# Make the filesystem read-only except for specific paths
ProtectSystem=strict

# Allow writing to the scoring engine directory (for database, logs)
ReadWritePaths={{ scoring_install_dir }}

# Give the service its own private /tmp directory
PrivateTmp=true

# ------------------------------------------------------------------------------
# [Install] Section - When to Enable the Service
# ------------------------------------------------------------------------------
# Defines which "target" (system state) should include this service

[Install]
# multi-user.target = normal system operation (like runlevel 3)
# This means: enable this service when the system boots to multi-user mode
WantedBy=multi-user.target
```

**Step 2: Commit**

```bash
git add ansible/roles/scoring_engine/templates/dwayne.service.j2
git commit -m "feat(scoring): add systemd service template

Configure auto-restart, journal logging, and security hardening."
```

---

## Task 5: Create TOML Configuration Template

**Files:**
- Create: `ansible/roles/scoring_engine/templates/dwayne.conf.j2`

**Step 1: Create the main configuration template**

```jinja2
# {{ ansible_managed }}
# DWAYNE-INATOR-5000 Configuration
# Generated from Ansible variables - do not edit manually

# ==============================================================================
# EVENT SETTINGS
# ==============================================================================
event = "{{ scoring_event_name }}"
verbose = {{ scoring_verbose | lower }}
timezone = "{{ scoring_timezone }}"
port = {{ scoring_port }}
startpaused = {{ scoring_start_paused | lower }}

# ==============================================================================
# TIMING SETTINGS
# ==============================================================================
delay = {{ scoring_delay }}
jitter = {{ scoring_jitter }}
timeout = {{ scoring_timeout }}
servicepoints = {{ scoring_service_points }}
slathreshold = {{ scoring_sla_threshold }}
slapoints = {{ scoring_sla_points }}

# ==============================================================================
# ADMIN ACCOUNTS
# ==============================================================================
{% for admin in scoring_admins %}
[[admin]]
name = "{{ admin.name }}"
pw = "{{ admin.password }}"

{% endfor %}
# ==============================================================================
# TEAMS
# ==============================================================================
{% for team in scoring_teams %}
[[team]]
ip = "{{ team.id }}"
pw = "{{ team.password }}"

{% endfor %}
# ==============================================================================
# CREDENTIAL LISTS
# ==============================================================================
{% for cred in scoring_credlists %}
[[creds]]
name = "{{ cred.name }}"
usernames = [{% for user in cred.usernames %}"{{ user }}"{% if not loop.last %}, {% endif %}{% endfor %}]
defaultpw = "{{ cred.default_password }}"

{% endfor %}
# ==============================================================================
# BOX CONFIGURATIONS
# ==============================================================================
{% for box in scoring_boxes %}
[[box]]
name = "{{ box.name }}"
ip = "{{ box.ip }}"

{% for check in box.checks %}
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
{# DNS Records #}
{% if check.records is defined %}
{% for record in check.records %}
        [[box.dns.record]]
        kind = "{{ record.kind }}"
        domain = "{{ record.domain }}"
        answer = [{% for ans in record.answer %}"{{ ans }}"{% if not loop.last %}, {% endif %}{% endfor %}]

{% endfor %}
{% endif %}
{# Web URLs #}
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
{# SSH/WinRM Commands #}
{% if check.commands is defined %}
{% for cmd in check.commands %}
        [[box.{{ check.type }}.command]]
        command = "{{ cmd.command }}"
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
{# SQL Queries #}
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
{# FTP/SMB Files #}
{% if check.files is defined %}
{% for file in check.files %}
        [[box.{{ check.type }}.file]]
        name = "{{ file.name }}"
{% if file.hash is defined %}
        hash = "{{ file.hash }}"
{% endif %}
{% if file.regex is defined %}
        regex = "{{ file.regex }}"
{% endif %}

{% endfor %}
{% endif %}
{% endfor %}
{% endfor %}
```

**Step 2: Commit**

```bash
git add ansible/roles/scoring_engine/templates/dwayne.conf.j2
git commit -m "feat(scoring): add TOML configuration template

Generate dwayne.conf from YAML variables with support for all
check types: ping, ssh, winrm, rdp, smb, dns, web, ftp, sql, ldap."
```

---

## Task 6: Create Playbook

**Files:**
- Create: `ansible/playbooks/setup-scoring-engine.yml`
- Modify: `ansible/playbooks/site.yml`

**Step 1: Create the scoring engine playbook**

```yaml
---
# ==============================================================================
# SETUP SCORING ENGINE PLAYBOOK
# ==============================================================================
# Deploys DWAYNE-INATOR-5000 scoring engine to Grey Team scoring servers.
#
# Usage:
#   ansible-playbook playbooks/setup-scoring-engine.yml
#
# After deployment:
#   - Access web interface at http://<scoring-ip>:8080
#   - Login as admin to unpause competition
#   - View logs: journalctl -fu dwayne-inator
#
# DOCUMENTATION:
# - DWAYNE-INATOR-5000: https://github.com/DSU-DefSec/DWAYNE-INATOR-5000

- name: Setup DWAYNE-INATOR-5000 Scoring Engine
  hosts: scoring
  become: true
  gather_facts: true

  pre_tasks:
    - name: Verify we have scoring configuration
      ansible.builtin.assert:
        that:
          - scoring_admins is defined
          - scoring_admins | length > 0
          - scoring_teams is defined
          - scoring_teams | length > 0
          - scoring_boxes is defined
        fail_msg: "Scoring configuration missing. Check group_vars/scoring.yml"
        success_msg: "Scoring configuration validated"

  roles:
    - scoring_engine

  post_tasks:
    - name: Display access information
      ansible.builtin.debug:
        msg:
          - "=============================================="
          - "SCORING ENGINE DEPLOYED SUCCESSFULLY"
          - "=============================================="
          - "Web Interface: http://{{ ansible_host }}:{{ scoring_port }}"
          - "Admin User: {{ scoring_admins[0].name }}"
          - "Competition Status: {{ 'PAUSED' if scoring_start_paused else 'RUNNING' }}"
          - ""
          - "Useful commands:"
          - "  View logs:    journalctl -fu dwayne-inator"
          - "  Stop:         systemctl stop dwayne-inator"
          - "  Start:        systemctl start dwayne-inator"
          - "  Status:       systemctl status dwayne-inator"
          - "=============================================="
```

**Step 2: Read site.yml to find where to add import**

Run: `cat ansible/playbooks/site.yml`

**Step 3: Add import to site.yml after setup-rdp-windows.yml**

Add this line after the last import_playbook:
```yaml
# Scoring engine (Grey Team)
- import_playbook: setup-scoring-engine.yml
```

**Step 4: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('ansible/playbooks/setup-scoring-engine.yml'))"`
Expected: No output (success)

**Step 5: Commit**

```bash
git add ansible/playbooks/setup-scoring-engine.yml ansible/playbooks/site.yml
git commit -m "feat(scoring): add setup-scoring-engine playbook

Create playbook for deploying scoring engine and integrate
into site.yml for full deployment workflow."
```

---

## Task 7: Create Scoring Directory Structure

**Files:**
- Create: `scoring/configs/checkfiles/.gitkeep`
- Create: `scoring/README.md`

**Step 1: Create configs directory structure**

Run: `mkdir -p scoring/configs/checkfiles`

**Step 2: Create .gitkeep for checkfiles**

Run: `touch scoring/configs/checkfiles/.gitkeep`

**Step 3: Create README for scoring directory**

```markdown
# Scoring Engine - A Beginner's Guide

Welcome! This guide will help you understand and use the DWAYNE-INATOR-5000 scoring engine for your Capture The Flag (CTF) or Cyber Defense Competition.

## What is a Scoring Engine?

A scoring engine is software that automatically checks if computer services are running correctly. In attack/defend competitions:

- **Blue Team** (defenders) tries to keep services running
- **Red Team** (attackers) tries to break into systems and disrupt services
- **Grey Team** (you!) runs the infrastructure and keeps score

The scoring engine periodically tests services (like websites, SSH servers, and file shares) and awards points when they're working. If services are down for too long, teams get penalties called "SLA violations" (Service Level Agreement violations).

## Competition Roles Explained

| Role | What They Do | Example Tasks |
|------|--------------|---------------|
| **Grey Team** | Run the competition | Set up infrastructure, monitor scoring, handle problems |
| **Blue Team** | Defend systems | Patch vulnerabilities, monitor for attacks, restore services |
| **Red Team** | Attack Blue Team | Find vulnerabilities, gain access, disrupt services |

## Directory Structure

```
scoring/
├── DWAYNE-INATOR-5000/     # The scoring engine source code (don't edit!)
├── configs/
│   └── checkfiles/          # Your custom files (SSH keys, scripts)
└── README.md                # This file
```

### What's a Git Submodule?

The `DWAYNE-INATOR-5000/` folder is a "git submodule" - it's a separate git repository included inside this one. This lets us:
- Keep the scoring engine code separate from our configuration
- Update to new versions easily
- Not worry about accidentally modifying the engine code

**Don't edit files in DWAYNE-INATOR-5000/** - your changes would be lost on updates!

## How to Configure the Scoring Engine

All configuration is in `ansible/group_vars/scoring.yml`. Here's what each section does:

### 1. Event Settings
```yaml
scoring_event_name: "My Competition"   # Shown on scoreboard
scoring_timezone: "America/New_York"   # For timestamps
scoring_start_paused: true             # Start paused? (recommended)
```

### 2. Timing Settings
```yaml
scoring_delay: 60          # Check services every 60 seconds
scoring_timeout: 10        # Wait 10 seconds for response
scoring_sla_threshold: 5   # 5 failures = SLA violation
```

### 3. Credential Lists
The engine needs usernames/passwords to test services:
```yaml
scoring_credlists:
  - name: "linux_users"
    usernames: ["cyberrange"]
    default_password: "Cyberrange123!"
```

### 4. Box Definitions
Define each server and what to check:
```yaml
scoring_boxes:
  - name: "webserver"
    ip: "10.10.10.31"
    checks:
      - type: ping          # Can we reach it?
      - type: ssh           # Can we log in?
      - type: web           # Is the website up?
```

## Deploying the Scoring Engine

### Prerequisites
1. You've run `tofu apply` to create the infrastructure
2. You've run `python3 import-tofu-to-ansible.py` to generate inventory
3. You've edited `ansible/group_vars/scoring.yml` with your settings

### Deploy Command
```bash
# Deploy just the scoring engine
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml

# Or deploy everything (including scoring engine)
ansible-playbook playbooks/site.yml
```

### What Happens During Deployment
1. **Installs Go** - The scoring engine is written in Go (a programming language)
2. **Copies source code** - Transfers files to the scoring server
3. **Compiles the engine** - Builds the executable program
4. **Generates config** - Creates `dwayne.conf` from your YAML settings
5. **Creates systemd service** - Sets up automatic start/restart
6. **Starts the service** - Launches the scoring engine

## Accessing the Scoreboard

Open a web browser and go to:
```
http://<scoring-server-ip>:8080
```

For example: `http://100.65.6.76:8080`

### Admin Login
- Use credentials from `scoring_admins` in your config
- Default: username `admin`, password `ScoringAdmin123!`

### Team Login
- Teams use credentials from `scoring_teams`
- Default: team ID `1`, password `BlueTeam123!`

## Operating the Scoring Engine

### Common Commands (run on scoring server via SSH)

```bash
# Check if scoring engine is running
systemctl status dwayne-inator

# View live logs (Ctrl+C to exit)
journalctl -fu dwayne-inator

# Stop the scoring engine
systemctl stop dwayne-inator

# Start the scoring engine
systemctl start dwayne-inator

# Restart the scoring engine
systemctl restart dwayne-inator
```

### Starting a Competition

1. **Before competition**: Verify all checks are passing in the admin panel
2. **Start time**: Click "Unpause" in the admin panel (or set `scoring_start_paused: false`)
3. **During competition**: Monitor the scoreboard and logs for issues
4. **End of competition**: Click "Pause" to stop scoring

### Resetting for a New Competition

If you need to start fresh:

```bash
# 1. Stop the scoring engine
systemctl stop dwayne-inator

# 2. Delete the database (this erases all scores!)
rm /opt/scoring-engine/dwayne.db

# 3. Start the scoring engine (creates new database)
systemctl start dwayne-inator
```

## Troubleshooting

### Service Won't Start
```bash
# Check for errors
journalctl -u dwayne-inator --no-pager | tail -50
```

Common issues:
- **Config syntax error**: Check your YAML in `group_vars/scoring.yml`
- **Port already in use**: Another service on port 8080
- **Permission denied**: Service user can't read files

### Checks Failing Unexpectedly
1. **Can you reach the box?** Try `ping 10.10.10.31` from scoring server
2. **Are credentials correct?** Verify usernames/passwords match the target
3. **Is the service running?** SSH to the box and check

### Score Not Updating
- Is the competition paused? Check admin panel
- Check logs: `journalctl -fu dwayne-inator`

## Supported Service Checks

| Check Type | What It Tests | Common Use |
|------------|---------------|------------|
| `ping` | Network connectivity (ICMP) | Basic "is it alive?" test |
| `ssh` | SSH login works | Linux server access |
| `winrm` | Windows Remote Management | Windows server management |
| `rdp` | Remote Desktop Protocol | Windows GUI access |
| `smb` | File sharing (Windows shares) | File server access |
| `dns` | DNS name resolution | Domain controller DNS |
| `web` | HTTP/HTTPS website response | Web servers |
| `ftp` | FTP file transfer | File servers |
| `sql` | Database queries (MySQL) | Database servers |
| `ldap` | Directory queries | Active Directory |
| `smtp` | Email sending | Mail servers |
| `imap` | Email retrieval | Mail servers |
| `tcp` | Port is open | Generic connectivity |
| `vnc` | VNC remote desktop | Linux GUI access |

## Adding Custom Checks

### SSH Key Authentication
1. Place private key in `scoring/configs/checkfiles/my_key`
2. Reference in config:
```yaml
- type: ssh
  privkey: "my_key"
```

### Custom Scripts
1. Create script in `scoring/configs/checkfiles/check_custom.py`
2. Use `cmd` check type:
```yaml
- type: cmd
  command: "python3 /opt/scoring-engine/checkfiles/check_custom.py"
  regex: "success"
```

## Learning More

- **DWAYNE-INATOR-5000 Docs**: [DWAYNE-INATOR-5000/README.md](DWAYNE-INATOR-5000/README.md)
- **Design Document**: [docs/plans/2026-01-18-scoring-engine-design.md](../docs/plans/2026-01-18-scoring-engine-design.md)
- **Ansible Documentation**: https://docs.ansible.com/
- **CCDC Info**: https://www.nationalccdc.org/

## Getting Help

If you're stuck:
1. Check the logs: `journalctl -fu dwayne-inator`
2. Review your configuration in `group_vars/scoring.yml`
3. Ask your instructor or team lead
4. Check the DWAYNE-INATOR-5000 GitHub issues
```

**Step 4: Commit**

```bash
git add scoring/configs/ scoring/README.md
git commit -m "docs(scoring): add scoring directory structure and README

Document configuration, deployment, operations, and supported checks."
```

---

## Task 8: Run Ansible Lint and Fix Issues

**Step 1: Run ansible-lint on new role**

Run: `cd ansible && ansible-lint roles/scoring_engine/ playbooks/setup-scoring-engine.yml`

**Step 2: Fix any reported issues**

Common fixes:
- Add `changed_when` to command tasks
- Use FQCN for all modules
- Fix line length issues

**Step 3: Commit fixes if needed**

```bash
git add ansible/
git commit -m "fix(scoring): address ansible-lint warnings"
```

---

## Task 9: Test Playbook Syntax

**Step 1: Run syntax check**

Run: `ansible-playbook ansible/playbooks/setup-scoring-engine.yml --syntax-check`
Expected: "playbook: ansible/playbooks/setup-scoring-engine.yml"

**Step 2: Run check mode (dry run)**

Run: `ansible-playbook ansible/playbooks/setup-scoring-engine.yml --check --diff`

Note: This will fail on some tasks that require actual execution (like go build), but validates the playbook structure.

---

## Task 10: Final Review and Merge Preparation

**Step 1: Review all changes**

Run: `git log --oneline main..HEAD`

**Step 2: Verify file structure**

Run: `find ansible/roles/scoring_engine -type f | sort`

Expected:
```
ansible/roles/scoring_engine/defaults/main.yml
ansible/roles/scoring_engine/handlers/main.yml
ansible/roles/scoring_engine/tasks/main.yml
ansible/roles/scoring_engine/templates/dwayne.conf.j2
ansible/roles/scoring_engine/templates/dwayne.service.j2
```

**Step 3: Run final lint**

Run: `./check.sh`

Note: Expect the pre-existing community.general.timezone warning. New code should pass.

**Step 4: Create summary commit message for merge/PR**

The feature branch is ready for merge with commits:
1. Centralized scoring configuration
2. Role structure (defaults, handlers)
3. Role tasks (install, build, deploy)
4. Systemd service template
5. TOML config template
6. Playbook and site.yml integration
7. Documentation and directory structure
