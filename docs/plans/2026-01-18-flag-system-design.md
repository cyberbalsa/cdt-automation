# Attack/Defend Flag System Design

## Overview

Add a plant-your-own flag mechanic to the scoring system that prevents "scorched earth" tactics. Red team must plant and maintain flags on compromised systems to earn points. Simply destroying services or locking out Blue team provides no benefit.

## Core Mechanics

### How It Works

1. Red team compromises a service and plants a `flag.txt` file in the service's directory
2. The flag file must contain Red's secret token (auto-generated at deploy time)
3. Scoring engine recursively searches the configured directory for valid flags
4. Flags only score points when the associated service check also passes

### Scoring Rules

- **Blue team**: Earns `scoring_service_points` each round for passing service checks (unchanged)
- **Red team**: Earns `scoring_flag_points` each flag-check interval for valid planted flags
- **Key constraint**: Flags only score when the service is UP
- Both teams can score on the same box simultaneously

### Example Scenario

| Situation | Blue Points | Red Points |
|-----------|-------------|------------|
| Web service UP, no flag | Yes | No |
| Web service UP, valid flag planted | Yes | Yes |
| Web service DOWN, valid flag planted | No | No |
| Web service UP, invalid/no flag | Yes | No |

This forces Red to maintain stealthy persistent access rather than destroying systems.

## Configuration

### New Variables in `group_vars/scoring.yml`

```yaml
# Flag system settings
scoring_flags_enabled: true              # Enable/disable flag system
scoring_flag_points: 5                   # Points per valid flag per check
scoring_flag_check_interval: 5           # Check flags every N service rounds
scoring_flag_filename: "flag.txt"        # Filename to search for
scoring_red_token_port: 8081             # Port for Red team token retrieval
```

### Per-Service Flag Paths

Each box definition includes a `flag_path` specifying where to search:

```yaml
scoring_boxes:
  - name: "webserver"
    ip: "10.10.10.31"
    flag_path: "/var/www/html"           # Recursive search root for flags
    checks:
      - type: web
        display: "HTTP"
        urls:
          - path: "/"
      - type: cmd
        display: "Flag"
        command: "/opt/scoring-engine/checkfiles/check_flag.py --service webserver-web --path /var/www/html"
        regex: "FLAG_VALID"
```

### Recommended Flag Paths by Service Type

| Service | Recommended `flag_path` |
|---------|------------------------|
| Web (Apache/Nginx) | `/var/www/html` or `/var/www` |
| SSH | `/etc/ssh` or `/home` |
| SMB/Samba | The shared directory path |
| FTP | FTP root directory |
| MySQL | `/var/lib/mysql` |
| DNS | `/etc/bind` or zone file directory |

## Implementation Components

### 1. Token Generation (Ansible Task)

During deployment, Ansible generates a random 32-character token:

```yaml
- name: Generate Red team token
  ansible.builtin.shell: |
    openssl rand -hex 16 > /opt/scoring-engine/red-token.txt
    chmod 600 /opt/scoring-engine/red-token.txt
  args:
    creates: /opt/scoring-engine/red-token.txt
```

### 2. Token Web Server (`token_server.py`)

Simple HTTP server serving the token for Red team automation:

```python
#!/usr/bin/env python3
"""Serve Red team token on a dedicated port."""
from http.server import HTTPServer, BaseHTTPRequestHandler
import sys

TOKEN_FILE = '/opt/scoring-engine/red-token.txt'

class TokenHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/token':
            try:
                with open(TOKEN_FILE, 'r') as f:
                    token = f.read().strip()
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(token.encode())
            except FileNotFoundError:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b'Token not found')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress logging

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    server = HTTPServer(('0.0.0.0', port), TokenHandler)
    print(f'Token server running on port {port}')
    server.serve_forever()
```

**Systemd service** (`token-server.service`):

```ini
[Unit]
Description=Red Team Token Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/scoring-engine
ExecStart=/usr/bin/python3 /opt/scoring-engine/token_server.py {{ scoring_red_token_port }}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Red team retrieves token**:
```bash
curl http://<scoring-server>:8081/token
```

### 3. Flag Checker Script (`check_flag.py`)

Core script that validates flags and checks service status:

```python
#!/usr/bin/env python3
"""
Flag checker for attack/defend scoring.
Validates that:
1. The associated service is UP (queries scoring DB)
2. A valid flag file exists in the search path
3. The flag contains the correct Red team token
"""
import argparse
import os
import sqlite3
import sys
import time
from pathlib import Path

DB_PATH = '/opt/scoring-engine/dwayne.db'
TOKEN_FILE = '/opt/scoring-engine/red-token.txt'
STATE_DIR = '/opt/scoring-engine/flag-state'

def get_service_status(db_path: str, service_name: str) -> bool:
    """Check if service passed its last check in scoring DB."""
    try:
        conn = sqlite3.connect(db_path, timeout=5)
        cursor = conn.cursor()
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
        return row[0] == 1 if row else False
    except sqlite3.Error:
        return False

def should_check_this_round(state_file: str, interval: int) -> bool:
    """Determine if we should check flags this round based on interval."""
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
    """Recursively search for a valid flag file."""
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
                    continue
    except (IOError, PermissionError):
        pass
    return False

def main():
    parser = argparse.ArgumentParser(description='Check for planted flags')
    parser.add_argument('--service', required=True, help='Service name (e.g., webserver-web)')
    parser.add_argument('--path', required=True, help='Directory to search for flags')
    parser.add_argument('--filename', default='flag.txt', help='Flag filename')
    parser.add_argument('--interval', type=int, default=5, help='Check every N rounds')
    parser.add_argument('--db', default=DB_PATH, help='Path to scoring database')
    parser.add_argument('--token-file', default=TOKEN_FILE, help='Path to token file')
    args = parser.parse_args()

    # Load expected token
    try:
        with open(args.token_file, 'r') as f:
            expected_token = f.read().strip()
    except FileNotFoundError:
        print("TOKEN_FILE_MISSING")
        sys.exit(0)

    # Check if this is a flag-check round
    state_file = f"{args.service.replace('-', '_')}.count"
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

### 4. Blue Team Aggregate Visibility

A separate check shows Blue team how many flags are planted (without revealing locations):

**`check_flag_count.py`**:

```python
#!/usr/bin/env python3
"""Count total planted flags for Blue team visibility."""
import json
import os
import sys

CONFIG_FILE = '/opt/scoring-engine/flag-paths.json'
TOKEN_FILE = '/opt/scoring-engine/red-token.txt'

def count_flags():
    with open(TOKEN_FILE, 'r') as f:
        token = f.read().strip()

    with open(CONFIG_FILE, 'r') as f:
        paths = json.load(f)  # {"webserver": "/var/www/html", ...}

    count = 0
    for box, search_path in paths.items():
        for root, dirs, files in os.walk(search_path):
            if 'flag.txt' in files:
                try:
                    with open(os.path.join(root, 'flag.txt'), 'r') as f:
                        if f.read().strip() == token:
                            count += 1
                            break
                except:
                    pass

    # Output format shows count to Blue team
    if count == 0:
        print("CLEAR")
    else:
        print(f"DETECTED_{count}")

if __name__ == '__main__':
    count_flags()
```

**Config entry** (shows on Blue's scoreboard):

```yaml
- name: "blue-status"
  ip: "10.10.10.21"
  checks:
    - type: cmd
      display: "Intrusion Alert"
      command: "/opt/scoring-engine/checkfiles/check_flag_count.py"
      regex: "CLEAR"  # Passes only when no flags detected
```

Blue sees this check fail with output like "DETECTED_3" when flags exist.

## File Structure

```
ansible/
├── files/
│   ├── check_flag.py           # Per-service flag checker
│   ├── check_flag_count.py     # Aggregate counter for Blue visibility
│   └── token_server.py         # HTTP server for Red token retrieval
├── roles/
│   └── scoring_engine/
│       ├── defaults/main.yml   # Add new flag variables
│       ├── tasks/main.yml      # Add token generation, deploy scripts
│       └── templates/
│           ├── dwayne.conf.j2  # Update with flag checks
│           ├── token-server.service.j2
│           └── flag-paths.json.j2
└── group_vars/
    └── scoring.yml             # Add flag configuration
```

## Deployment Flow

1. **Generate token**: Ansible creates random token at `/opt/scoring-engine/red-token.txt`
2. **Deploy scripts**: Copy `check_flag.py`, `check_flag_count.py`, `token_server.py` to scoring server
3. **Generate flag-paths.json**: Template with all box→path mappings for the counter script
4. **Start token server**: Enable and start systemd service on configured port
5. **Generate config**: Include flag `cmd` checks in `dwayne.conf`

## Security Considerations

- Token file is readable only by the scoring engine user
- Token server runs on a dedicated port (8081) separate from scoreboard (8080)
- Red team must have network access to scoring server to retrieve token
- Flag validation is server-side; Red cannot fake flags without the token

## Testing Checklist

- [ ] Token generated on deployment
- [ ] Token server accessible at `http://<scoring>:8081/token`
- [ ] Flag check skips when service is down
- [ ] Flag check awards points when service is up and flag is valid
- [ ] Flag check interval works (checks every N rounds)
- [ ] Blue team sees aggregate flag count
- [ ] Invalid flag content is rejected
- [ ] Flag in wrong location is not found

## Future Enhancements

- Multiple Red teams with separate tokens
- Per-service token rotation
- Flag expiration (must re-plant periodically)
- Admin panel showing all flag locations
- Points decay for stale flags
