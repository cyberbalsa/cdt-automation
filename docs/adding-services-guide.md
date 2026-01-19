# Adding Services to the Scoring System - Complete Guide

**For students new to Ansible, Terraform, and CTF infrastructure**

This guide walks you through adding each type of service to your competition infrastructure step by step. No prior experience required!

---

## Table of Contents

1. [Understanding the Basics](#understanding-the-basics)
2. [The 4-Step Process](#the-4-step-process)
3. [Service Guides](#service-guides)
   - [Ping (Basic Connectivity)](#ping-basic-connectivity)
   - [SSH (Linux Remote Access)](#ssh-linux-remote-access)
   - [WinRM (Windows Remote Access)](#winrm-windows-remote-access)
   - [RDP (Remote Desktop)](#rdp-remote-desktop)
   - [Web Server (HTTP)](#web-server-http)
   - [DNS (Domain Name System)](#dns-domain-name-system)
   - [LDAP (Directory Services)](#ldap-directory-services)
   - [SMB (Windows File Sharing)](#smb-windows-file-sharing)
   - [FTP (File Transfer)](#ftp-file-transfer)
   - [SQL (Database)](#sql-database)
   - [Mail (Email - SMTP/IMAP)](#mail-email---smtpimap)
   - [IRC (Chat Server)](#irc-chat-server)
   - [VNC (Linux Remote Desktop)](#vnc-linux-remote-desktop)
4. [Adding Red Team Flag Checks](#adding-red-team-flag-checks)
5. [Known Issues and Workarounds](#known-issues-and-workarounds)
6. [Troubleshooting](#troubleshooting)
7. [Quick Reference](#quick-reference)

---

## Understanding the Basics

### What is a Scoring Engine?

In a Capture The Flag (CTF) competition, a **scoring engine** automatically checks if services are working. Think of it like a robot that:
- Visits your website every minute to check if it loads
- Tries to log into your SSH server to verify it accepts connections
- Pings your servers to make sure they're online

If a service works, your team gets points. If it's down, you don't.

### What Files Do I Need to Edit?

You only need to edit **2 files** to add a new service:

| File | What It Does | When to Edit |
|------|--------------|--------------|
| `opentofu/variables.tf` | Tells the system which services run on which servers | Always |
| `ansible/group_vars/scoring_overrides.yml` | Customizes how a service is checked | Only if you need special settings |

### What Commands Do I Run?

After editing files, run these commands:

```bash
# Step 1: Go to the project folder
cd /root/cdt-automation

# Step 2: Regenerate the inventory
python3 import-tofu-to-ansible.py

# Step 3: Update the scoring engine
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml

# Step 4: Verify it worked
ansible-playbook playbooks/validate-scoreboard.yml
```

---

## The 4-Step Process

Every service follows the same basic process:

### Step 1: Find the service_hosts Section

Open `opentofu/variables.tf` and find this section:

```hcl
variable "service_hosts" {
  description = "Map of service names to lists of hostnames"
  default = {
    ping   = []                 # Empty = all boxes
    ssh    = []                 # Empty = all Linux boxes
    winrm  = []                 # Empty = all Windows boxes
    rdp    = []                 # Empty = all Windows boxes
    dns    = ["dc01"]
    ldap   = ["dc01"]
    smb    = ["dc01", "wks-alpha"]
    ftp    = ["webserver"]
    web    = ["webserver"]
    sql    = ["comms"]
    mail   = ["comms"]
    irc    = ["comms"]
  }
}
```

### Step 2: Add Your Server to the Service

Add your server's hostname to the list:

```hcl
web = ["webserver", "my-new-server"]  # Added my-new-server
```

### Step 3: Regenerate the Configuration

```bash
cd /root/cdt-automation
python3 import-tofu-to-ansible.py
```

### Step 4: Deploy and Verify

```bash
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
ansible-playbook playbooks/validate-scoreboard.yml
```

---

## Service Guides

---

### Ping (Basic Connectivity)

**What it checks:** Can the scoring server reach your server at all? (ICMP ping)

**Default behavior:** ALL servers are automatically pinged. You don't need to add anything!

**Port:** N/A (uses ICMP protocol, not TCP ports)

#### Adding Ping to a Specific Server

If you only want certain servers pinged (not all), list them explicitly:

**Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    ping = ["dc01", "webserver", "comms"]  # Only these 3 servers
  }
}
```

#### Regenerate and Deploy

```bash
cd /root/cdt-automation
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

#### Troubleshooting Ping

**Problem:** Ping checks fail on Windows servers

**Solution:** Run the firewall playbook to enable ICMP:
```bash
ansible-playbook playbooks/setup-windows-firewall.yml
```

This creates a Windows Firewall rule to allow ping responses.

---

### SSH (Linux Remote Access)

**What it checks:** Can we log into this Linux server via SSH?

**Default behavior:** All Linux servers automatically get SSH checks.

**Port:** 22

**Credentials used:** `linux_users` credlist (username: `cyberrange`, password: `Cyberrange123!`)

#### Adding SSH to a Specific Server

Usually you don't need to do anything - SSH is automatic for Linux boxes.

To explicitly list SSH servers:

**Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    ssh = ["webserver", "comms", "my-linux-box"]
  }
}
```

#### Regenerate and Deploy

```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

#### Troubleshooting SSH

**Problem:** SSH check fails with "authentication failed"

**Solution:** The `cyberrange` user must exist with the correct password:
```bash
# On the target Linux server
sudo useradd -m cyberrange
echo "cyberrange:Cyberrange123!" | sudo chpasswd
```

---

### WinRM (Windows Remote Access)

**What it checks:** Can we run PowerShell commands on this Windows server remotely?

**Default behavior:** All Windows servers automatically get WinRM checks.

**Port:** 5985 (HTTP) or 5986 (HTTPS)

**Credentials used:** `admins` credlist (username: `Administrator`, password: `Cyberrange123!`)

#### Adding WinRM to a Specific Server

Usually automatic for Windows boxes. To be explicit:

**Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    winrm = ["dc01", "wks-alpha", "wks-debbie"]
  }
}
```

#### Regenerate and Deploy

```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

#### Troubleshooting WinRM

**Problem:** WinRM check fails

**Solution 1:** Verify WinRM is enabled on the Windows server:
```powershell
# Run on the Windows server (as Administrator)
winrm quickconfig -force
```

**Solution 2:** Check the Administrator password matches:
```powershell
# Reset Administrator password
net user Administrator Cyberrange123!
```

---

### RDP (Remote Desktop)

**What it checks:** Is Remote Desktop Protocol accepting connections?

**Default behavior:** All Windows servers automatically get RDP checks.

**Port:** 3389

**Credentials used:** None (only checks if port is open)

#### Adding RDP to a Server

**Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    rdp = ["dc01", "wks-alpha"]  # Windows servers with RDP
  }
}
```

#### For Linux Servers (xRDP)

Linux can also serve RDP via xRDP:

```bash
# First, install xRDP on the Linux server
ansible-playbook playbooks/setup-rdp-linux.yml

# Then add to service_hosts
```

**Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    rdp = ["dc01", "wks-alpha", "webserver"]  # Including Linux server
  }
}
```

#### Regenerate and Deploy

```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

---

### Web Server (HTTP)

**What it checks:** Does the website load correctly?

**Port:** 80 (HTTP) or 443 (HTTPS)

**Default check:** Requests `/` and expects HTTP status 200 (OK)

#### Adding a Web Server

**Step 1: Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    web = ["webserver", "my-new-webserver"]
  }
}
```

**Step 2: Install a web server on the target machine:**
```bash
# Install Apache on the new server
ansible my-new-webserver -b -m apt -a "name=apache2 state=present"
ansible my-new-webserver -b -m service -a "name=apache2 state=started"
```

**Step 3: Regenerate and deploy:**
```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

#### Customizing Web Checks

To check specific pages or look for specific content:

**Edit `ansible/group_vars/scoring_overrides.yml`:**
```yaml
scoring_box_overrides:
  my-new-webserver:
    web:
      - type: web
        urls:
          - path: "/"
            status: 200
          - path: "/login"
            status: 200
          - path: "/api/health"
            status: 200
            regex: "healthy"  # Page must contain this text
```

---

### DNS (Domain Name System)

**What it checks:** Can the server resolve domain names correctly?

**Port:** 53

**Special requirement:** You MUST specify which DNS records to check!

#### Adding a DNS Server

**Step 1: Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    dns = ["dc01", "my-dns-server"]
  }
}
```

**Step 2: Configure DNS records to check in `ansible/group_vars/scoring_overrides.yml`:**
```yaml
scoring_box_overrides:
  my-dns-server:
    dns:
      - type: dns
        records:
          - kind: "A"                    # A record (hostname to IP)
            domain: "www.example.com"    # Domain to look up
            answer: ["10.10.10.50"]      # Expected IP address(es)
          - kind: "A"
            domain: "mail.example.com"
            answer: ["10.10.10.51"]
```

**Step 3: Regenerate and deploy:**
```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

#### DNS Record Types

| Kind | Description | Example |
|------|-------------|---------|
| `A` | Hostname to IPv4 address | `www.example.com` -> `10.10.10.50` |
| `AAAA` | Hostname to IPv6 address | `www.example.com` -> `2001:db8::1` |
| `MX` | Mail server for domain | `example.com` -> `mail.example.com` |
| `CNAME` | Alias for another hostname | `blog.example.com` -> `www.example.com` |

---

### LDAP (Directory Services)

**What it checks:** Is the LDAP directory service responding?

**Port:** 389

**Note:** Due to a bug in the scoring engine, LDAP is checked using a TCP port check instead of a full LDAP query.

#### Adding LDAP

**Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    ldap = ["dc01"]  # Usually only the Domain Controller
  }
}
```

#### Regenerate and Deploy

```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

#### How the Check Works

The default check verifies TCP port 389 is open:
```yaml
# From scoring_services.yml (already configured)
ldap:
  - type: tcp
    port: 389
    display: "ldap"
```

---

### SMB (Windows File Sharing)

**What it checks:** Is Windows file sharing (SMB) available?

**Port:** 445

#### Adding SMB

**Step 1: Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    smb = ["dc01", "wks-alpha", "fileserver"]
  }
}
```

**Step 2: Enable SMB on the Windows server:**
```bash
ansible-playbook playbooks/setup-smb.yml
```

**Step 3: Regenerate and deploy:**
```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

#### What the Playbook Does

The `setup-smb.yml` playbook:
1. Starts the Server (LanmanServer) service
2. Enables "File and Printer Sharing" firewall rules
3. Creates a shared folder at `C:\CTFShare`

---

### FTP (File Transfer)

**What it checks:** Can we log into the FTP server and list files?

**Port:** 21

**Credentials used:** `linux_users` credlist

#### Adding FTP

**Step 1: Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    ftp = ["webserver", "fileserver"]
  }
}
```

**Step 2: Install an FTP server:**
```bash
# Install vsftpd on the target server
ansible fileserver -b -m apt -a "name=vsftpd state=present"
ansible fileserver -b -m service -a "name=vsftpd state=started enabled=yes"
```

**Step 3: Configure vsftpd to allow local users:**
```bash
ansible fileserver -b -m lineinfile -a "path=/etc/vsftpd.conf regexp='^local_enable' line='local_enable=YES'"
ansible fileserver -b -m service -a "name=vsftpd state=restarted"
```

**Step 4: Regenerate and deploy:**
```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

---

### SQL (Database)

**What it checks:** Can we connect to MySQL/MariaDB and verify a database exists?

**Port:** 3306

**Credentials used:** `linux_users` credlist

**Default check:** Verifies a database named `scoring_test` exists

#### Adding SQL

**Step 1: Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    sql = ["comms", "database-server"]
  }
}
```

**Step 2: Install MySQL/MariaDB:**
```bash
ansible database-server -b -m apt -a "name=mariadb-server state=present"
ansible database-server -b -m service -a "name=mariadb state=started enabled=yes"
```

**Step 3: Create the scoring user and database:**
```bash
ansible database-server -b -m shell -a "mysql -e \"CREATE DATABASE IF NOT EXISTS scoring_test; CREATE USER IF NOT EXISTS 'cyberrange'@'%' IDENTIFIED BY 'Cyberrange123!'; GRANT ALL ON scoring_test.* TO 'cyberrange'@'%'; FLUSH PRIVILEGES;\""
```

**Step 4: Allow remote connections:**
```bash
ansible database-server -b -m lineinfile -a "path=/etc/mysql/mariadb.conf.d/50-server.cnf regexp='^bind-address' line='bind-address = 0.0.0.0'"
ansible database-server -b -m service -a "name=mariadb state=restarted"
```

**Step 5: Regenerate and deploy:**
```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

#### Checking a Different Database

To check a database with a different name:

**Edit `ansible/group_vars/scoring_overrides.yml`:**
```yaml
scoring_box_overrides:
  database-server:
    sql:
      - type: sql
        credlists: ["linux_users"]
        queries:
          - database: "my_app_database"
            databaseexists: true
```

---

### Mail (Email - SMTP/IMAP)

**What it checks:** Are the email ports open? (SMTP port 25, IMAP port 143)

**Ports:** 25 (SMTP) and 143 (IMAP)

**Note:** Due to bugs in the scoring engine, mail is checked using TCP port checks instead of full email protocol tests.

#### Adding Mail

**Step 1: Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    mail = ["comms", "mail-server"]
  }
}
```

**Step 2: Install mail server software:**
```bash
# Install Postfix (SMTP) and Dovecot (IMAP)
ansible mail-server -b -m apt -a "name=postfix,dovecot-imapd state=present"
ansible mail-server -b -m service -a "name=postfix state=started enabled=yes"
ansible mail-server -b -m service -a "name=dovecot state=started enabled=yes"
```

**Step 3: Regenerate and deploy:**
```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

#### How the Check Works

The mail service creates TWO checks:
```yaml
# From scoring_services.yml (already configured)
mail:
  - type: tcp
    port: 25
    display: "smtp"
  - type: tcp
    port: 143
    display: "imap"
```

---

### IRC (Chat Server)

**What it checks:** Is the IRC server port open?

**Port:** 6667

#### Adding IRC

**Step 1: Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    irc = ["comms", "chat-server"]
  }
}
```

**Step 2: Install an IRC server:**
```bash
# Install ngIRCd
ansible chat-server -b -m apt -a "name=ngircd state=present"
ansible chat-server -b -m service -a "name=ngircd state=started enabled=yes"
```

**Step 3: Regenerate and deploy:**
```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

---

### VNC (Linux Remote Desktop)

**What it checks:** Is VNC accepting connections?

**Port:** 5900 (display :0) or 5901 (display :1)

#### Adding VNC

**Step 1: Edit `opentofu/variables.tf`:**
```hcl
variable "service_hosts" {
  default = {
    vnc = ["linux-desktop"]
  }
}
```

**Step 2: Install a VNC server:**
```bash
# Install TigerVNC
ansible linux-desktop -b -m apt -a "name=tigervnc-standalone-server state=present"
```

**Step 3: Regenerate and deploy:**
```bash
python3 import-tofu-to-ansible.py
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml
```

---

## Adding Red Team Flag Checks

Flag checks validate that Red Team has planted flags on compromised systems.

### How Flags Work

1. Red Team compromises a server
2. Red Team creates a file containing a secret token
3. Scoring engine reads the file and checks for the token
4. If the token matches, Red Team gets points!

### Adding a Flag Check

**Edit `ansible/group_vars/scoring_overrides.yml`:**

#### For Linux Servers (using SSH):
```yaml
scoring_box_overrides:
  webserver:
    extra_checks:
      - type: ssh
        display: "flag"
        credlists: ["linux_users"]
        commands:
          - command: "cat /var/www/html/flag.txt 2>/dev/null || echo NOT_FOUND"
            contains: true
            output: "{{ red_team_token }}"
```

#### For Windows Servers (using WinRM):
```yaml
scoring_box_overrides:
  dc01:
    extra_checks:
      - type: winrm
        display: "flag"
        credlists: ["admins"]
        commands:
          - command: "Get-Content C:\\Users\\Public\\flag.txt"
            contains: true
            output: "{{ red_team_token }}"
```

### Changing the Flag Token

**Edit `ansible/group_vars/scoring.yml`:**
```yaml
# Change this for each competition!
red_team_token: "YOUR-SECRET-TOKEN-HERE"
```

---

## Known Issues and Workarounds

The DWAYNE-INATOR-5000 scoring engine has some bugs. Here are the workarounds:

### Ping Fails on Some Windows Servers

**Problem:** The go-ping library has issues with some network configurations.

**Workaround (already applied):** The ping check uses `allowpacketloss: true` with `percent: 101`:
```yaml
ping:
  - type: ping
    count: 1
    allowpacketloss: true
    percent: 101
```

### IMAP Check Fails

**Problem:** Bug in DWAYNE code uses wrong format specifier for port.

**Workaround (already applied):** Changed to TCP port check:
```yaml
mail:
  - type: tcp
    port: 143
    display: "imap"
```

### SMTP Check Fails

**Problem:** Bug requires sender/receiver fields that weren't supported.

**Workaround (already applied):** Changed to TCP port check:
```yaml
mail:
  - type: tcp
    port: 25
    display: "smtp"
```

### LDAP Check Fails

**Problem:** Bug in domain parsing requires exactly 2 parts.

**Workaround (already applied):** Changed to TCP port check:
```yaml
ldap:
  - type: tcp
    port: 389
    display: "ldap"
```

### Duplicate Check Name Error

**Problem:** Multiple TCP checks on the same server cause "duplicate check name" errors.

**Workaround (already applied):** All TCP checks include a `display` field:
```yaml
ldap:
  - type: tcp
    port: 389
    display: "ldap"  # Makes check name unique
```

---

## Troubleshooting

### Service Shows "DOWN" But It's Running

**Step 1: Test connectivity from the scoring server:**
```bash
# SSH into the scoring server
ssh cyberrange@scoring-1

# Test TCP connectivity
nc -zv <target-ip> <port>
# Example: nc -zv 10.10.10.102 25
```

**Step 2: Check if the service is listening:**
```bash
# On the target server
ss -tlnp | grep <port>
# Example: ss -tlnp | grep 25
```

**Step 3: Check for firewall issues:**
```bash
# On Linux
sudo ufw status
sudo iptables -L INPUT -n

# On Windows (PowerShell)
Get-NetFirewallRule | Where-Object {$_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound'}
```

### Scoreboard Shows Old Data

**Problem:** Scoring is paused or using stale data.

**Solution:** Check if scoring is running:
```bash
cd ansible
ansible scoring -m shell -a "curl -s http://localhost:8080 | grep -i paused"
```

If paused, edit `ansible/group_vars/scoring.yml`:
```yaml
scoring_start_paused: false
```

Then redeploy:
```bash
ansible-playbook playbooks/setup-scoring-engine.yml
```

### Service Not in Scoreboard at All

**Checklist:**

1. Is the hostname in `service_hosts`?
   ```bash
   grep -A30 "service_hosts" opentofu/variables.tf | grep your-service
   ```

2. Did you regenerate the inventory?
   ```bash
   python3 import-tofu-to-ansible.py
   ```

3. Does the host have `host_services` in inventory?
   ```bash
   grep "your-hostname" ansible/inventory/production.ini
   ```

4. Did you redeploy the scoring engine?
   ```bash
   ansible-playbook playbooks/setup-scoring-engine.yml
   ```

### Check the Scoring Engine Logs

```bash
ansible scoring -b -m shell -a "journalctl -u dwayne-inator --no-pager -n 50"
```

---

## Quick Reference

### Commands Cheat Sheet

```bash
# Regenerate inventory after editing variables.tf
python3 import-tofu-to-ansible.py

# Deploy scoring engine configuration
ansible-playbook playbooks/setup-scoring-engine.yml

# Validate scoreboard
ansible-playbook playbooks/validate-scoreboard.yml

# View scoring engine logs
ansible scoring -b -m shell -a "journalctl -fu dwayne-inator"

# Test connectivity from scoring server
ansible scoring -m shell -a "nc -zv <ip> <port>"

# Check what services a host has
grep "host_services" ansible/inventory/production.ini

# List all hosts in a service group
ansible <service> --list-hosts
```

### File Locations

| File | Purpose |
|------|---------|
| `opentofu/variables.tf` | Define which services run on which servers |
| `ansible/group_vars/scoring_services.yml` | Default check definitions for each service |
| `ansible/group_vars/scoring_overrides.yml` | Custom checks for specific servers |
| `ansible/group_vars/scoring.yml` | Scoring engine settings (timing, credentials, etc.) |
| `ansible/inventory/production.ini` | Auto-generated server inventory |

### Service Ports Quick Reference

| Service | Port(s) | Protocol |
|---------|---------|----------|
| Ping | N/A | ICMP |
| SSH | 22 | TCP |
| FTP | 21 | TCP |
| DNS | 53 | TCP/UDP |
| HTTP | 80 | TCP |
| HTTPS | 443 | TCP |
| IMAP | 143 | TCP |
| LDAP | 389 | TCP |
| SMB | 445 | TCP |
| RDP | 3389 | TCP |
| MySQL | 3306 | TCP |
| WinRM | 5985/5986 | TCP |
| VNC | 5900+ | TCP |
| IRC | 6667 | TCP |

### Credential Lists

| Name | Username | Default Password | Used For |
|------|----------|------------------|----------|
| `linux_users` | cyberrange | Cyberrange123! | SSH, FTP, SQL |
| `admins` | Administrator | Cyberrange123! | WinRM, Windows services |
| `domain_users` | jdoe, asmith, etc. | UserPass123! | Domain user logins |

---

## Getting Help

1. **Check the logs:** Most issues show up in the scoring engine logs
2. **Test connectivity:** Use `nc -zv` to verify ports are reachable
3. **Verify configuration:** Check that `host_services` is set correctly in the inventory
4. **Ask the team:** Your Grey Team/instructor can help debug infrastructure issues
