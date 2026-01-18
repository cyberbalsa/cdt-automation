# Flag Check Refactor Design

**Date:** 2026-01-18
**Status:** Approved

## Overview

Refactor flag checking to use DWAYNE-INATOR-5000's built-in file/command validation instead of the separate Python `check_flag.py` script. This simplifies the architecture by leveraging existing SSH command checks and SMB file checks.

## Current State

- `check_flag.py` - Standalone Python script that:
  - Queries the scoring database to check if a service is UP
  - Searches for flag files on the local filesystem
  - Validates flag content against a token file
  - Has rate limiting (check every N rounds)
- `check_flag_count.py` - Displays flag counts for Blue team visibility
- Token stored in `/opt/scoring-engine/red-token.txt`

## New Design

Use existing DWAYNE-INATOR-5000 check types for flag validation:

| Box Type | Check Type | Mechanism |
|----------|------------|-----------|
| Linux | SSH command | `cat /path/to/flag.txt` with `contains` or `regex` validation |
| Windows | SMB file | Read from share with `regex` validation |

### Key Benefits

1. **No custom code** - Uses existing, tested check types
2. **Unified scoring** - Flag checks scored identically to service checks
3. **Implicit service dependency** - If SSH/SMB login fails, flag check fails
4. **Single config source** - All scoring in `group_vars/scoring.yml`

## Configuration

### Token Variable

Add to `ansible/group_vars/scoring.yml`:

```yaml
# Red team token for flag validation
red_team_token: "REDTEAM-SECRET-2026"
```

### Linux Flag Checks (SSH)

```yaml
- name: "webserver"
  ip: "10.10.10.31"
  checks:
    - type: ssh
      credlists: ["domain_users"]
    - type: ssh
      display: "flag"
      credlists: ["domain_users"]
      commands:
        - command: "cat /var/www/html/flag.txt"
          contains: true
          output: "{{ red_team_token }}"
```

### Windows Flag Checks (SMB)

```yaml
- name: "dc01"
  ip: "10.10.10.21"
  checks:
    - type: smb
      credlists: ["admins"]
    - type: smb
      display: "flag"
      credlists: ["admins"]
      share: "C$"
      files:
        - name: "Users\\Public\\flag.txt"
          regex: "{{ red_team_token }}"
```

## Template Changes

Update `ansible/roles/scoring_engine/templates/dwayne.conf.j2` to handle:

1. **SSH commands** - `[[box.ssh.command]]` blocks with `command`, `contains`, `output`, `useregex` fields
2. **SMB files** - `[[box.smb.file]]` blocks with `name`, `hash`, `regex` fields
3. **SMB share** - `share` field on SMB checks

## Files to Remove

- `ansible/files/check_flag.py` - No longer needed
- `ansible/files/check_flag_count.py` - No longer needed
- Related deployment tasks for these scripts
- Token file deployment (`/opt/scoring-engine/red-token.txt`)

## Implementation Tasks

1. Update `dwayne.conf.j2` template to support SSH commands and SMB files
2. Add `red_team_token` variable to `group_vars/scoring.yml`
3. Add example flag checks to `scoring_boxes` configuration
4. Remove `check_flag.py` and `check_flag_count.py`
5. Remove flag-related tasks from `scoring_engine` role
6. Update `scoring/README.md` documentation
7. Test flag detection via SSH and SMB checks

## Example Full Box Configuration

```yaml
scoring_boxes:
  # Linux web server with flag check
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
      - type: ssh
        display: "flag"
        credlists: ["domain_users"]
        commands:
          - command: "cat /var/www/html/flag.txt"
            contains: true
            output: "{{ red_team_token }}"

  # Windows DC with flag check
  - name: "dc01"
    ip: "10.10.10.21"
    checks:
      - type: ping
      - type: winrm
        credlists: ["admins"]
      - type: rdp
      - type: smb
        credlists: ["admins"]
      - type: smb
        display: "flag"
        credlists: ["admins"]
        share: "C$"
        files:
          - name: "Users\\Public\\flag.txt"
            regex: "{{ red_team_token }}"
```
