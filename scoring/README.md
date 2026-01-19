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

## Flag System (Attack/Defend Mechanics)

The flag system adds attack/defend mechanics where Red Team must maintain persistent access to score points - they can't just destroy everything!

### Why Do We Need This?

Without flags, Red Team can simply:
1. Break into a system
2. Delete everything or crash services
3. Blue Team loses points, Red Team doesn't care

With flags:
1. Red Team must maintain **stealthy** access
2. Breaking services stops Red Team's flag points too!
3. Blue Team is incentivized to hunt for flags, not just keep services running

This mirrors real-world scenarios where attackers want to maintain persistent access for data theft or espionage, not just cause destruction.

### How It Works

Flag checking uses the **built-in DWAYNE-INATOR-5000 check types** - no custom scripts required!

- **Linux boxes**: SSH command checks run `cat /path/to/flag.txt` and validate the output contains the token
- **Windows boxes**: SMB file checks read from Windows shares and validate content with regex

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLAG SYSTEM FLOW                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   GREY TEAM (Before Competition)                                 │
│   ──────────────────────────────                                 │
│   1. Set red_team_token in group_vars/scoring.yml               │
│   2. Configure flag checks for each box                         │
│   3. Distribute token to Red Team (secure channel)              │
│                                                                  │
│   RED TEAM                         SCORING SERVER                │
│   ────────                         ──────────────                │
│                                                                  │
│   1. Receive token from Grey Team                               │
│      (In-person briefing, sealed envelope, etc.)                │
│                                                                  │
│   2. Compromise a box                                           │
│      (SSH, exploit, etc.)                                       │
│                                                                  │
│   3. Plant flag ────────────────►  Blue Team Box                │
│      echo "REDTEAM-CTF-2026" > /var/www/html/flag.txt          │
│                                                                  │
│   4. Keep access (don't break it!)                              │
│                                                                  │
│                                    Every scoring round:         │
│                                    ┌─────────────────────┐      │
│                                    │ SSH/SMB Check       │      │
│                                    └──────────┬──────────┘      │
│                                               │                  │
│                                    ┌──────────▼──────────┐      │
│                                    │ Read flag file      │      │
│                                    └──────────┬──────────┘      │
│                                               │                  │
│                              FOUND            │      NOT FOUND  │
│                              ┌────────────────▼────────────┐    │
│                              │ Does content contain token? │    │
│                              └────────────────┬────────────┘    │
│                                               │                  │
│                              YES              │             NO  │
│                              ▼                ▼                 │
│                         Check PASS       Check FAIL             │
│                         (Red scores!)    (No points)            │
│                                                                  │
│   BLUE TEAM                                                      │
│   ─────────                                                      │
│   5. See flag checks on scoreboard                              │
│   6. Hunt for flag files: find / -name "flag.txt"               │
│   7. Remove enemy flags: rm /var/www/html/flag.txt              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Configuration

Configure in `ansible/group_vars/scoring.yml`:

```yaml
# Red team token for flag validation
# This token must appear in flag files for Red Team to score points
# Change this for each competition!
red_team_token: "REDTEAM-CTF-2026"
```

Add flag checks to boxes using SSH (Linux) or SMB (Windows):

**Linux Flag Check (SSH):**
```yaml
scoring_boxes:
  - name: "webserver"
    ip: "10.10.10.31"
    checks:
      - type: ping
      - type: ssh
        credlists: ["linux_users"]

      # Flag check - uses SSH to read the flag file
      - type: ssh
        display: "flag"
        credlists: ["linux_users"]
        commands:
          - command: "cat /var/www/html/flag.txt 2>/dev/null || echo NOT_FOUND"
            contains: true
            output: "{{ red_team_token }}"
```

**Windows Flag Check (SMB):**
```yaml
scoring_boxes:
  - name: "fileserver"
    ip: "10.10.10.22"
    checks:
      - type: ping
      - type: winrm
        credlists: ["admins"]

      # Flag check - uses SMB to read the flag file from a share
      - type: smb
        display: "flag"
        credlists: ["admins"]
        domain: "CDT.local"
        file:
          name: "C$/flags/flag.txt"     # UNC path: \\server\C$\flags\flag.txt
          regex: "{{ red_team_token }}"
```

### Red Team Instructions

```bash
# Step 1: Get your token from Grey Team
# (Provided during competition briefing - NOT available via network!)
TOKEN="REDTEAM-CTF-2026"

# Step 2: Compromise a target system (out of scope for this guide!)

# Step 3: Plant a flag (must have write access to the configured path)
echo "$TOKEN" > /var/www/html/flag.txt

# Step 4: Verify your flag is planted
cat /var/www/html/flag.txt

# Step 5: Keep your access! Don't break the service or Blue Team might
#         notice and kick you out. Stealthy persistence is the goal.

# Tips:
# - Check the scoring config to know WHERE to plant flags
# - The flag must be in the exact path configured for each box
# - If you break the service (SSH/SMB), you stop earning flag points!
# - Be subtle - obvious flags are easy for Blue Team to find
```

### Blue Team Defense

```bash
# Hunt for enemy flags across the entire system
find / -name "flag.txt" 2>/dev/null

# Check common locations
ls -la /var/www/html/
ls -la /home/
ls -la /tmp/

# Remove enemy flags when found
rm /var/www/html/flag.txt

# Monitor for new files being created (requires inotify-tools)
inotifywait -m -r /var/www/html -e create -e modify

# Check the scoreboard for flag check results
# A passing flag check means Red Team has access!
```

### Understanding the Scoreboard

Flag checks appear as regular service checks with the display name "flag":

| Status | Meaning | Who It Helps |
|--------|---------|--------------|
| `flag: PASS` | Red has a valid flag planted | Red Team (they're scoring!) |
| `flag: FAIL` | No valid flag found | Blue Team (they're clear or Red lost access) |
| `flag: TIMEOUT` | SSH/SMB connection failed | Neither (service may be down) |

### Troubleshooting Flag Issues

**Red Team: "My flag isn't scoring"**
1. Is the SSH/SMB service UP? Check the main service check first
2. Is your token correct? It must match `red_team_token` exactly
3. Is the flag in the exact path configured? Check the `command` or `file.name` in the config
4. Is the file readable by the scoring credentials? Check permissions

**Blue Team: "Flag check is passing but I can't find the flag"**
1. Check the exact path in the scoring config
2. Look for hidden files: `ls -la`
3. Check if it's in a subdirectory
4. Verify you're on the right box

**Grey Team: "Flag checks not working"**
1. Can you manually SSH/SMB to the box with the scoring credentials?
2. Is the token value correct in `group_vars/scoring.yml`?
3. Did you redeploy after changing config? `ansible-playbook playbooks/setup-scoring-engine.yml`
4. Check scoring engine logs: `journalctl -fu dwayne-inator`

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
