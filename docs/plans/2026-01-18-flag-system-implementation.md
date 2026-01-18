# Flag System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add attack/defend flag mechanics to the scoring engine that require Red team to maintain persistent access (not just destroy services) to earn points.

**Architecture:** Uses existing DWAYNE-INATOR-5000 `cmd` check type with custom Python scripts. Scripts query the scoring database to verify services are up before awarding flag points. Token server provides automated retrieval for Red team tooling.

**Tech Stack:** Python 3, SQLite3, Ansible, systemd

---

## Task 1: Add Flag System Default Variables

**Files:**
- Modify: `ansible/roles/scoring_engine/defaults/main.yml`

**Step 1: Add flag system variables to defaults**

Add these variables at the end of the file:

```yaml
# ------------------------------------------------------------------------------
# FLAG SYSTEM SETTINGS
# ------------------------------------------------------------------------------
# Attack/defend flag mechanics - Red team plants flags, Blue team hunts them.
# Flags only score when the associated service is UP (prevents scorched earth).

# Enable/disable the flag system
scoring_flags_enabled: false

# Points awarded per valid flag per check interval
scoring_flag_points: 5

# Check flags every N service rounds (e.g., 5 = every 5 minutes if delay=60)
scoring_flag_check_interval: 5

# Filename to search for when checking flags
scoring_flag_filename: "flag.txt"

# Port for Red team token retrieval server
scoring_red_token_port: 8081
```

**Step 2: Verify syntax**

Run: `cd /root/cdt-automation/.worktrees/flag-system && python3 -c "import yaml; yaml.safe_load(open('ansible/roles/scoring_engine/defaults/main.yml'))"`

Expected: No output (success)

**Step 3: Commit**

```bash
git add ansible/roles/scoring_engine/defaults/main.yml
git commit -m "feat(scoring): add flag system default variables"
```

---

## Task 2: Create Flag Checker Script

**Files:**
- Create: `ansible/files/check_flag.py`

**Step 1: Create the script**

```python
#!/usr/bin/env python3
"""
Flag checker for attack/defend scoring.

Validates that:
1. The associated service is UP (queries scoring DB)
2. A valid flag file exists in the search path
3. The flag contains the correct Red team token

Usage:
    check_flag.py --service webserver-web --path /var/www/html

Exit codes match scoring engine expectations:
- Outputs "FLAG_VALID" when flag found and service up
- Outputs "SERVICE_DOWN" when service check failed
- Outputs "FLAG_NOT_FOUND" when no valid flag exists
- Outputs "SKIP_INTERVAL" when not time to check yet
"""
import argparse
import os
import sqlite3
import sys
from pathlib import Path

# Default paths (can be overridden via arguments)
DB_PATH = '/opt/scoring-engine/dwayne.db'
TOKEN_FILE = '/opt/scoring-engine/red-token.txt'
STATE_DIR = '/opt/scoring-engine/flag-state'


def get_service_status(db_path: str, service_name: str) -> bool:
    """Check if service passed its last check in scoring DB.

    Args:
        db_path: Path to the DWAYNE-INATOR-5000 SQLite database
        service_name: Name of the service check (e.g., "webserver-web")

    Returns:
        True if service is UP, False otherwise
    """
    try:
        conn = sqlite3.connect(db_path, timeout=5)
        cursor = conn.cursor()

        # Query the most recent result for this service
        # result_entries.status: 1 = UP, 0 = DOWN
        cursor.execute("""
            SELECT re.status
            FROM result_entries re
            JOIN team_records tr ON tr.id = re.team_record_id
            WHERE re.name = ?
              AND tr.round = (SELECT MAX(round) FROM team_records)
            LIMIT 1
        """, (service_name,))

        row = cursor.fetchone()
        conn.close()

        # status is stored as integer: 1 = true/up, 0 = false/down
        return row[0] == 1 if row else False

    except sqlite3.Error as e:
        # If we can't read the database, assume service status unknown
        print(f"DB_ERROR: {e}", file=sys.stderr)
        return False


def should_check_this_round(state_file: str, interval: int) -> bool:
    """Determine if we should check flags this round based on interval.

    Tracks a counter in a state file. Returns True every N calls.

    Args:
        state_file: Filename for state tracking (in STATE_DIR)
        interval: Check every N rounds

    Returns:
        True if this is a check round, False to skip
    """
    os.makedirs(STATE_DIR, exist_ok=True)
    state_path = os.path.join(STATE_DIR, state_file)

    try:
        with open(state_path, 'r') as f:
            count = int(f.read().strip())
    except (FileNotFoundError, ValueError):
        count = 0

    count += 1

    with open(state_path, 'w') as f:
        f.write(str(count))

    return count % interval == 0


def find_valid_flag(search_path: str, filename: str, expected_token: str) -> bool:
    """Recursively search for a valid flag file.

    Args:
        search_path: Root directory to search
        filename: Flag filename to look for
        expected_token: Expected contents of the flag file

    Returns:
        True if valid flag found, False otherwise
    """
    try:
        for root, dirs, files in os.walk(search_path):
            if filename in files:
                flag_path = os.path.join(root, filename)
                try:
                    with open(flag_path, 'r') as f:
                        content = f.read().strip()
                        if content == expected_token:
                            return True
                except (IOError, PermissionError):
                    # Can't read this file, continue searching
                    continue
    except (IOError, PermissionError):
        # Can't access search path
        pass

    return False


def main():
    parser = argparse.ArgumentParser(
        description='Check for planted flags in attack/defend scoring'
    )
    parser.add_argument(
        '--service',
        required=True,
        help='Service name to check status of (e.g., webserver-web)'
    )
    parser.add_argument(
        '--path',
        required=True,
        help='Directory to recursively search for flags'
    )
    parser.add_argument(
        '--filename',
        default='flag.txt',
        help='Flag filename to search for (default: flag.txt)'
    )
    parser.add_argument(
        '--interval',
        type=int,
        default=5,
        help='Check every N rounds (default: 5)'
    )
    parser.add_argument(
        '--db',
        default=DB_PATH,
        help='Path to scoring database'
    )
    parser.add_argument(
        '--token-file',
        default=TOKEN_FILE,
        help='Path to Red team token file'
    )

    args = parser.parse_args()

    # Load expected token
    try:
        with open(args.token_file, 'r') as f:
            expected_token = f.read().strip()
    except FileNotFoundError:
        print("TOKEN_FILE_MISSING")
        sys.exit(0)

    # Check if this is a flag-check round
    state_file = f"{args.service.replace('-', '_').replace('.', '_')}.count"
    if not should_check_this_round(state_file, args.interval):
        print("SKIP_INTERVAL")
        sys.exit(0)

    # Check if service is up
    if not get_service_status(args.db, args.service):
        print("SERVICE_DOWN")
        sys.exit(0)

    # Search for valid flag
    if find_valid_flag(args.path, args.filename, expected_token):
        print("FLAG_VALID")
    else:
        print("FLAG_NOT_FOUND")


if __name__ == '__main__':
    main()
```

**Step 2: Make executable and test syntax**

Run: `chmod +x ansible/files/check_flag.py && python3 -m py_compile ansible/files/check_flag.py`

Expected: No output (success)

**Step 3: Commit**

```bash
git add ansible/files/check_flag.py
git commit -m "feat(scoring): add flag checker script"
```

---

## Task 3: Create Flag Counter Script (Blue Visibility)

**Files:**
- Create: `ansible/files/check_flag_count.py`

**Step 1: Create the script**

```python
#!/usr/bin/env python3
"""
Count total planted flags for Blue team visibility.

Searches all configured flag paths and counts valid flags.
Blue team sees aggregate count but not specific locations.

Usage:
    check_flag_count.py

Output:
    "CLEAR" - No flags detected (check passes)
    "DETECTED_N" - N flags found (check fails, shown to Blue)
"""
import json
import os
import sys

CONFIG_FILE = '/opt/scoring-engine/flag-paths.json'
TOKEN_FILE = '/opt/scoring-engine/red-token.txt'


def count_flags() -> int:
    """Count valid flags across all configured paths.

    Returns:
        Number of valid flags found
    """
    # Load token
    try:
        with open(TOKEN_FILE, 'r') as f:
            token = f.read().strip()
    except FileNotFoundError:
        return 0

    # Load flag paths configuration
    try:
        with open(CONFIG_FILE, 'r') as f:
            config = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return 0

    paths = config.get('paths', {})
    filename = config.get('filename', 'flag.txt')

    count = 0
    for box_name, search_path in paths.items():
        # Search this box's flag path
        try:
            for root, dirs, files in os.walk(search_path):
                if filename in files:
                    flag_path = os.path.join(root, filename)
                    try:
                        with open(flag_path, 'r') as f:
                            if f.read().strip() == token:
                                count += 1
                                break  # Only count one flag per box
                    except (IOError, PermissionError):
                        continue
        except (IOError, PermissionError):
            continue

    return count


def main():
    count = count_flags()

    if count == 0:
        print("CLEAR")
    else:
        print(f"DETECTED_{count}")


if __name__ == '__main__':
    main()
```

**Step 2: Make executable and test syntax**

Run: `chmod +x ansible/files/check_flag_count.py && python3 -m py_compile ansible/files/check_flag_count.py`

Expected: No output (success)

**Step 3: Commit**

```bash
git add ansible/files/check_flag_count.py
git commit -m "feat(scoring): add flag counter script for Blue visibility"
```

---

## Task 4: Create Token Server Script

**Files:**
- Create: `ansible/files/token_server.py`

**Step 1: Create the script**

```python
#!/usr/bin/env python3
"""
Simple HTTP server to serve Red team token.

Runs on a dedicated port so Red team can automate token retrieval.
No authentication - access controlled by network position.

Usage:
    token_server.py [port]

Example:
    token_server.py 8081

Red team retrieves token:
    curl http://<scoring-server>:8081/token
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import sys

TOKEN_FILE = '/opt/scoring-engine/red-token.txt'


class TokenHandler(BaseHTTPRequestHandler):
    """HTTP handler that serves the Red team token."""

    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/token':
            try:
                with open(TOKEN_FILE, 'r') as f:
                    token = f.read().strip()

                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.send_header('Content-Length', len(token))
                self.end_headers()
                self.wfile.write(token.encode())

            except FileNotFoundError:
                self.send_response(500)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Token not configured')
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Not found. Use GET /token')

    def log_message(self, format, *args):
        """Suppress default logging to avoid cluttering output."""
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081

    server = HTTPServer(('0.0.0.0', port), TokenHandler)
    print(f'Token server running on port {port}')
    print(f'Red team can retrieve token at: http://<server>:{port}/token')

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nShutting down...')
        server.shutdown()


if __name__ == '__main__':
    main()
```

**Step 2: Make executable and test syntax**

Run: `chmod +x ansible/files/token_server.py && python3 -m py_compile ansible/files/token_server.py`

Expected: No output (success)

**Step 3: Commit**

```bash
git add ansible/files/token_server.py
git commit -m "feat(scoring): add token server for Red team automation"
```

---

## Task 5: Create Token Server Systemd Template

**Files:**
- Create: `ansible/roles/scoring_engine/templates/token-server.service.j2`

**Step 1: Create the template**

```ini
# {{ ansible_managed }}
# Red Team Token Server
# Serves the flag token on a dedicated port for automated retrieval

[Unit]
Description=Red Team Token Server
Documentation=file://{{ scoring_install_dir }}/token_server.py
After=network.target
# Start after scoring engine so token file exists
After={{ scoring_service_name }}.service

[Service]
Type=simple
User={{ scoring_service_user }}
WorkingDirectory={{ scoring_install_dir }}
ExecStart=/usr/bin/python3 {{ scoring_install_dir }}/token_server.py {{ scoring_red_token_port }}
Restart=always
RestartSec=5

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths={{ scoring_install_dir }}

[Install]
WantedBy=multi-user.target
```

**Step 2: Commit**

```bash
git add ansible/roles/scoring_engine/templates/token-server.service.j2
git commit -m "feat(scoring): add token server systemd service template"
```

---

## Task 6: Create Flag Paths JSON Template

**Files:**
- Create: `ansible/roles/scoring_engine/templates/flag-paths.json.j2`

**Step 1: Create the template**

```jinja2
{{ ansible_managed | to_json }}
{
  "filename": "{{ scoring_flag_filename }}",
  "paths": {
{% for box in scoring_boxes %}
{% if box.flag_path is defined %}
    "{{ box.name }}": "{{ box.flag_path }}"{% if not loop.last %},{% endif %}

{% endif %}
{% endfor %}
  }
}
```

**Step 2: Commit**

```bash
git add ansible/roles/scoring_engine/templates/flag-paths.json.j2
git commit -m "feat(scoring): add flag paths JSON template"
```

---

## Task 7: Update Scoring Engine Tasks for Flag System

**Files:**
- Modify: `ansible/roles/scoring_engine/tasks/main.yml`

**Step 1: Add flag system tasks after existing tasks**

Add these tasks at the end of the file (before the final closing):

```yaml
# ==============================================================================
# FLAG SYSTEM DEPLOYMENT (Optional)
# ==============================================================================
# These tasks deploy the attack/defend flag system components.
# Only runs when scoring_flags_enabled is true.

- name: Generate Red team token
  ansible.builtin.shell: |
    openssl rand -hex 16 > {{ scoring_install_dir }}/red-token.txt
    chmod 600 {{ scoring_install_dir }}/red-token.txt
  args:
    creates: "{{ scoring_install_dir }}/red-token.txt"
  when: scoring_flags_enabled | default(false)

- name: Create flag state directory
  ansible.builtin.file:
    path: "{{ scoring_install_dir }}/flag-state"
    state: directory
    owner: "{{ scoring_service_user }}"
    mode: "0755"
  when: scoring_flags_enabled | default(false)

- name: Deploy flag checker script
  ansible.builtin.copy:
    src: check_flag.py
    dest: "{{ scoring_install_dir }}/checkfiles/check_flag.py"
    owner: "{{ scoring_service_user }}"
    mode: "0755"
  when: scoring_flags_enabled | default(false)

- name: Deploy flag counter script
  ansible.builtin.copy:
    src: check_flag_count.py
    dest: "{{ scoring_install_dir }}/checkfiles/check_flag_count.py"
    owner: "{{ scoring_service_user }}"
    mode: "0755"
  when: scoring_flags_enabled | default(false)

- name: Deploy token server script
  ansible.builtin.copy:
    src: token_server.py
    dest: "{{ scoring_install_dir }}/token_server.py"
    owner: "{{ scoring_service_user }}"
    mode: "0755"
  when: scoring_flags_enabled | default(false)

- name: Deploy flag paths configuration
  ansible.builtin.template:
    src: flag-paths.json.j2
    dest: "{{ scoring_install_dir }}/flag-paths.json"
    owner: "{{ scoring_service_user }}"
    mode: "0644"
  when: scoring_flags_enabled | default(false)

- name: Deploy token server systemd service
  ansible.builtin.template:
    src: token-server.service.j2
    dest: /etc/systemd/system/red-token-server.service
    owner: root
    mode: "0644"
  notify:
    - Reload systemd
  when: scoring_flags_enabled | default(false)

- name: Enable and start token server
  ansible.builtin.systemd:
    name: red-token-server
    enabled: true
    state: started
    daemon_reload: true
  when: scoring_flags_enabled | default(false)

- name: Display flag system status
  ansible.builtin.debug:
    msg: |
      Flag system enabled!
      - Token server: http://{{ ansible_host }}:{{ scoring_red_token_port }}/token
      - Flag filename: {{ scoring_flag_filename }}
      - Check interval: Every {{ scoring_flag_check_interval }} rounds
      - Points per flag: {{ scoring_flag_points }}
  when: scoring_flags_enabled | default(false)
```

**Step 2: Verify syntax**

Run: `cd /root/cdt-automation/.worktrees/flag-system && ansible-playbook --syntax-check ansible/playbooks/setup-scoring-engine.yml 2>&1 | head -5`

Expected: "playbook: ansible/playbooks/setup-scoring-engine.yml" (syntax OK)

**Step 3: Commit**

```bash
git add ansible/roles/scoring_engine/tasks/main.yml
git commit -m "feat(scoring): add flag system deployment tasks"
```

---

## Task 8: Add Handler for Systemd Reload

**Files:**
- Check/Modify: `ansible/roles/scoring_engine/handlers/main.yml`

**Step 1: Verify handlers exist (should already have Reload systemd)**

Run: `cat ansible/roles/scoring_engine/handlers/main.yml`

If "Reload systemd" handler doesn't exist, add it. The file should contain:

```yaml
---
# Handlers for scoring_engine role

- name: Reload systemd
  ansible.builtin.systemd:
    daemon_reload: true

- name: Restart scoring engine
  ansible.builtin.systemd:
    name: "{{ scoring_service_name }}"
    state: restarted
```

**Step 2: Commit if changed**

```bash
git add ansible/roles/scoring_engine/handlers/main.yml
git commit -m "fix(scoring): ensure systemd reload handler exists"
```

---

## Task 9: Update scoring.yml with Flag Configuration Example

**Files:**
- Modify: `ansible/group_vars/scoring.yml`

**Step 1: Add flag system configuration section**

Add after the BOX DEFINITIONS section:

```yaml
# ------------------------------------------------------------------------------
# FLAG SYSTEM CONFIGURATION (Attack/Defend)
# ------------------------------------------------------------------------------
# Enable the flag system to add attack/defend mechanics:
# - Red team plants flag.txt files with their secret token
# - Flags only score when the associated service is UP
# - Blue team sees aggregate count but not locations
#
# HOW IT WORKS:
# 1. Red retrieves token: curl http://<scoring-server>:8081/token
# 2. Red plants flag: echo "<token>" > /var/www/html/flag.txt
# 3. Scoring engine checks flag paths every N rounds
# 4. If service UP + valid flag = Red earns points
# 5. Blue sees "DETECTED_N" on their scoreboard

scoring_flags_enabled: true
scoring_flag_points: 5
scoring_flag_check_interval: 5
scoring_flag_filename: "flag.txt"
scoring_red_token_port: 8081
```

**Step 2: Add flag_path to box definitions**

Update the webserver box to include flag_path:

```yaml
  - name: "webserver"
    ip: "10.10.10.31"
    flag_path: "/var/www/html"    # Red plants flags here
    checks:
      - type: ping
      - type: ssh
        credlists: ["linux_users"]
      - type: web
        urls:
          - path: "/"
            status: 200
      # Flag check - runs as cmd type, awards points for valid flag
      - type: cmd
        display: "Flag"
        command: "/opt/scoring-engine/checkfiles/check_flag.py --service webserver-web --path /var/www/html --interval 5"
        regex: "FLAG_VALID"
```

**Step 3: Add flag_path to blue-linux-2:**

```yaml
  - name: "blue-linux-2"
    ip: "10.10.10.32"
    flag_path: "/home"            # Red plants flags here
    checks:
      - type: ping
      - type: ssh
        credlists: ["linux_users"]
      # Flag check
      - type: cmd
        display: "Flag"
        command: "/opt/scoring-engine/checkfiles/check_flag.py --service blue-linux-2-ssh --path /home --interval 5"
        regex: "FLAG_VALID"
```

**Step 4: Verify syntax**

Run: `cd /root/cdt-automation/.worktrees/flag-system && python3 -c "import yaml; yaml.safe_load(open('ansible/group_vars/scoring.yml'))"`

Expected: No output (success)

**Step 5: Commit**

```bash
git add ansible/group_vars/scoring.yml
git commit -m "feat(scoring): add flag system configuration to scoring.yml"
```

---

## Task 10: Update Documentation

**Files:**
- Modify: `scoring/README.md`

**Step 1: Add Flag System section**

Add after "Adding Custom Checks" section:

```markdown
## Flag System (Attack/Defend)

The flag system adds attack/defend mechanics where Red team must maintain persistent access to score points.

### How It Works

1. **Red retrieves token**: `curl http://<scoring-server>:8081/token`
2. **Red plants flag**: `echo "<token>" > /var/www/html/flag.txt`
3. **Scoring engine checks** flag paths every N rounds (configurable)
4. **Points awarded** only if service is UP and flag is valid
5. **Blue sees** aggregate count ("3 flags detected") but not locations

### Why This Matters

Without flags, Red team can simply destroy services to deny Blue points. With flags:
- Red must maintain stealthy access to keep scoring
- Breaking services stops Red's flag points too
- Blue is incentivized to hunt for flags, not just keep services running

### Configuration

Enable in `ansible/group_vars/scoring.yml`:

```yaml
scoring_flags_enabled: true
scoring_flag_points: 5           # Points per flag per check
scoring_flag_check_interval: 5   # Check every 5 service rounds
scoring_flag_filename: "flag.txt"
scoring_red_token_port: 8081     # Token retrieval port
```

Add `flag_path` to each box:

```yaml
scoring_boxes:
  - name: "webserver"
    ip: "10.10.10.31"
    flag_path: "/var/www/html"   # Where Red plants flags
    checks:
      - type: web
        # ...
      - type: cmd
        display: "Flag"
        command: "/opt/scoring-engine/checkfiles/check_flag.py --service webserver-web --path /var/www/html"
        regex: "FLAG_VALID"
```

### Red Team Usage

```bash
# Get your token
TOKEN=$(curl -s http://<scoring-server>:8081/token)

# Plant a flag (must have write access to the path)
echo "$TOKEN" > /var/www/html/flag.txt

# Verify flag exists
cat /var/www/html/flag.txt
```

### Blue Team Defense

- Monitor for suspicious files in service directories
- Check for `flag.txt` files: `find /var/www -name "flag.txt"`
- Remove enemy flags: `rm /var/www/html/flag.txt`
- Watch the scoreboard for "DETECTED" alerts
```

**Step 2: Commit**

```bash
git add scoring/README.md
git commit -m "docs(scoring): add flag system documentation"
```

---

## Task 11: Final Integration Commit

**Step 1: Review all changes**

Run: `git log --oneline main..HEAD`

Expected: 9-10 commits for the flag system

**Step 2: Create integration summary commit (optional)**

If desired, squash or add a summary:

```bash
git log --oneline main..HEAD
```

---

## Verification Checklist

After implementation, verify:

- [ ] `ansible/roles/scoring_engine/defaults/main.yml` has flag variables
- [ ] `ansible/files/check_flag.py` exists and is executable
- [ ] `ansible/files/check_flag_count.py` exists and is executable
- [ ] `ansible/files/token_server.py` exists and is executable
- [ ] `ansible/roles/scoring_engine/templates/token-server.service.j2` exists
- [ ] `ansible/roles/scoring_engine/templates/flag-paths.json.j2` exists
- [ ] `ansible/roles/scoring_engine/tasks/main.yml` has flag deployment tasks
- [ ] `ansible/group_vars/scoring.yml` has flag configuration
- [ ] `scoring/README.md` has flag system documentation
- [ ] All Python scripts pass syntax check
- [ ] Ansible playbook passes syntax check

---

## Deployment Test (Optional)

If you have a scoring server available:

```bash
cd ansible
ansible-playbook playbooks/setup-scoring-engine.yml -v

# Verify token server
curl http://<scoring-ip>:8081/token

# Verify scripts deployed
ssh <scoring-server> ls -la /opt/scoring-engine/checkfiles/
```
