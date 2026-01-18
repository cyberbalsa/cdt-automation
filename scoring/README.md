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
