# DWAYNE-INATOR-5000 Scoring Engine Integration

**Date:** 2026-01-18
**Status:** Approved

## Overview

Integrate the DWAYNE-INATOR-5000 scoring engine into the CDT automation infrastructure using Ansible. The scoring engine runs on the Grey Team scoring server and monitors Blue Team services during attack/defend competitions.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Configuration management | Ansible templates | Keep scoring config in sync with infrastructure |
| Check definitions | Centralized in `group_vars/scoring.yml` | Easy to review/edit all scoring in one place |
| Team structure | Single team mode | Simpler for training, one Blue Team defends |
| Default checks | Standard CCDC-style | SSH, WinRM, RDP, SMB, DNS, web |
| Deployment method | Systemd service | Reliable, auto-restart, standard logging |
| HTTPS | HTTP only | Isolated lab network, simpler setup |
| Passwords | Inline | Lab environment, no Ansible Vault needed |

## Directory Structure

```
scoring/
├── DWAYNE-INATOR-5000/     # Git submodule
├── configs/                 # Competition-specific configs
│   ├── dwayne.conf.j2      # Main config template
│   ├── injects.conf.j2     # Injects template (optional)
│   └── checkfiles/          # SSH keys, scripts for checks
└── README.md

ansible/
├── roles/
│   └── scoring_engine/
│       ├── tasks/main.yml
│       ├── defaults/main.yml
│       ├── templates/
│       │   ├── dwayne.conf.j2
│       │   └── dwayne.service.j2
│       └── handlers/main.yml
├── group_vars/
│   └── scoring.yml          # Centralized scoring configuration
└── playbooks/
    └── setup-scoring-engine.yml
```

## Centralized Scoring Configuration

File: `ansible/group_vars/scoring.yml`

```yaml
# Event settings
scoring_event_name: "CDT Attack/Defend Competition"
scoring_timezone: "America/New_York"
scoring_start_paused: true

# Timing
scoring_delay: 60
scoring_jitter: 5
scoring_timeout: 10
scoring_service_points: 10
scoring_sla_threshold: 5
scoring_sla_points: 10

# Admin accounts
scoring_admins:
  - name: admin
    password: "ScoringAdmin123!"

# Team (single team mode)
scoring_teams:
  - id: "1"
    password: "BlueTeam123!"

# Credential lists for service checks
scoring_credlists:
  - name: "domain_users"
    usernames: ["jdoe", "asmith", "bwilson"]
    default_password: "UserPass123!"
  - name: "admins"
    usernames: ["Administrator"]
    default_password: "Cyberrange123!"

# Box definitions with checks
scoring_boxes:
  - name: "dc01"
    ip: "10.10.10.21"
    checks:
      - type: ping
      - type: winrm
        credlists: ["admins"]
      - type: rdp
      - type: smb
        credlists: ["admins"]
      - type: dns
        records:
          - kind: "A"
            domain: "dc01.CDT.local"
            answer: ["10.10.10.21"]

  - name: "blue-win-2"
    ip: "10.10.10.22"
    checks:
      - type: ping
      - type: winrm
        credlists: ["admins"]
      - type: rdp

  - name: "webserver"
    ip: "10.10.10.31"
    checks:
      - type: ping
      - type: ssh
        credlists: ["domain_users"]
      - type: web
        urls:
          - path: "/"
            status: 200

  - name: "blue-linux-2"
    ip: "10.10.10.32"
    checks:
      - type: ping
      - type: ssh
        credlists: ["domain_users"]
```

## Ansible Role Tasks

File: `ansible/roles/scoring_engine/tasks/main.yml`

1. Install dependencies (golang-go, gcc, git)
2. Copy DWAYNE-INATOR-5000 source to `/opt/scoring-engine/`
3. Build the binary with `go build`
4. Generate config from template
5. Deploy systemd service
6. Enable and start service

## Systemd Service

File: `ansible/roles/scoring_engine/templates/dwayne.service.j2`

```ini
[Unit]
Description=DWAYNE-INATOR-5000 Scoring Engine
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/scoring-engine
ExecStart=/opt/scoring-engine/dwayne-inator
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dwayne-inator
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/opt/scoring-engine

[Install]
WantedBy=multi-user.target
```

## Config Template

File: `ansible/roles/scoring_engine/templates/dwayne.conf.j2`

Converts YAML configuration to TOML format using Jinja2 templating. Handles:
- Event settings and timing
- Admin and team definitions
- Credential lists
- Box definitions with nested checks
- Check-specific fields (DNS records, web URLs, etc.)

## Playbook Integration

File: `ansible/playbooks/setup-scoring-engine.yml`

```yaml
---
- name: Setup DWAYNE-INATOR-5000 Scoring Engine
  hosts: scoring
  become: yes
  roles:
    - scoring_engine
```

Add to `site.yml` after other playbooks:
```yaml
- import_playbook: setup-scoring-engine.yml
```

## Usage Workflow

1. Deploy infrastructure: `tofu apply`
2. Generate inventory: `python3 import-tofu-to-ansible.py`
3. Edit `group_vars/scoring.yml` with competition settings
4. Run: `ansible-playbook playbooks/site.yml`
5. Access scoring at: `http://<scoring-server-ip>:8080`
6. Unpause competition from admin panel when ready

## Operator Commands

```bash
# View logs
journalctl -fu dwayne-inator

# Stop/start scoring
systemctl stop dwayne-inator
systemctl start dwayne-inator

# Check status
systemctl status dwayne-inator
```

## Future Enhancements

- Add injects.conf.j2 template for competition challenges
- Support multi-team mode with dynamic IP ranges
- Add HTTPS support with Let's Encrypt or self-signed certs
- Create competition reset/cleanup playbook
