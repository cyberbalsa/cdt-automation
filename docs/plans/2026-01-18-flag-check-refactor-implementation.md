# Flag Check Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace custom Python flag checking scripts with DWAYNE-INATOR-5000's built-in SSH command and SMB file checks.

**Architecture:** Use SSH `command` checks for Linux boxes (cat flag file, validate token) and SMB `file` checks for Windows boxes (read from share, validate with regex). Token defined as Ansible variable.

**Tech Stack:** Ansible, Jinja2 templates, TOML config

---

## Task 1: Add SMB Share Support to Template

**Files:**
- Modify: `ansible/roles/scoring_engine/templates/dwayne.conf.j2:145-158`

**Step 1: Update the SMB file section to include share field**

In `dwayne.conf.j2`, find the FTP/SMB Files section (around line 145) and add share support before the files loop:

```jinja2
{# FTP/SMB Files #}
{% if check.share is defined %}
    share = "{{ check.share }}"
{% endif %}
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
```

**Step 2: Run linter to verify**

Run: `cd /root/cdt-automation/.worktrees/flag-check-refactor && ./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/roles/scoring_engine/templates/dwayne.conf.j2
git commit -m "feat(scoring): add SMB share field support to config template"
```

---

## Task 2: Update Scoring Configuration

**Files:**
- Modify: `ansible/group_vars/scoring.yml`

**Step 1: Add red_team_token variable**

After the `scoring_red_token_port` line (around line 366), add:

```yaml
# Red team token for flag validation
# This token must appear in flag files for Red Team to score points
# Change this for each competition!
red_team_token: "REDTEAM-CTF-2026"
```

**Step 2: Replace webserver flag check**

Find the webserver box (around line 255) and replace the `type: cmd` flag check with an SSH command check:

Before:
```yaml
      - type: cmd
        display: "Flag"
        command: "/opt/scoring-engine/checkfiles/check_flag.py --service webserver-web --path /var/www/html --interval 5"
        regex: "FLAG_VALID"
```

After:
```yaml
      - type: ssh
        display: "flag"
        credlists: ["linux_users"]
        commands:
          - command: "cat /var/www/html/flag.txt 2>/dev/null || echo NOT_FOUND"
            contains: true
            output: "{{ red_team_token }}"
```

**Step 3: Replace blue-linux-2 flag check**

Find the blue-linux-2 box (around line 298) and replace similarly:

Before:
```yaml
      - type: cmd
        display: "Flag"
        command: "/opt/scoring-engine/checkfiles/check_flag.py --service blue-linux-2-ssh --path /home --interval 5"
        regex: "FLAG_VALID"
```

After:
```yaml
      - type: ssh
        display: "flag"
        credlists: ["linux_users"]
        commands:
          - command: "cat /home/flag.txt 2>/dev/null || echo NOT_FOUND"
            contains: true
            output: "{{ red_team_token }}"
```

**Step 4: Remove obsolete flag_path fields**

Remove these lines from box definitions:
- `flag_path: "/var/www/html"` (webserver)
- `flag_path: "/home"` (blue-linux-2)

**Step 5: Remove obsolete flag system variables**

Delete or comment out these variables (around lines 314-366):
- `scoring_flags_enabled`
- `scoring_flag_points`
- `scoring_flag_check_interval`
- `scoring_flag_filename`
- `scoring_red_token_port`

Keep only `red_team_token`.

**Step 6: Run linter**

Run: `cd /root/cdt-automation/.worktrees/flag-check-refactor && ./check.sh`
Expected: All checks passed

**Step 7: Commit**

```bash
git add ansible/group_vars/scoring.yml
git commit -m "feat(scoring): replace cmd flag checks with SSH command checks

- Add red_team_token variable for flag validation
- Replace type: cmd checks with type: ssh command checks
- Remove obsolete flag system variables (scoring_flags_enabled, etc.)
- Remove flag_path fields from box definitions"
```

---

## Task 3: Remove Flag System Tasks from Role

**Files:**
- Modify: `ansible/roles/scoring_engine/tasks/main.yml`

**Step 1: Delete FLAG SYSTEM section**

Remove the entire section from line 223 to end of file (lines 223-421). This removes:
- FLAG STEP 1: Generate Red Team Token
- FLAG STEP 2: Create State Directory
- FLAG STEP 3: Create Checkfiles Directory
- FLAG STEP 4: Deploy Flag Checker Script
- FLAG STEP 5: Deploy Flag Counter Script
- FLAG STEP 6: Deploy Token Server Script
- FLAG STEP 7: Deploy Flag Paths Configuration
- FLAG STEP 8: Deploy Token Server Systemd Service
- FLAG STEP 9: Enable and Start Token Server
- FLAG STEP 10: Display Flag System Status

The file should end after the "Display service status" debug task (line 221).

**Step 2: Run linter**

Run: `cd /root/cdt-automation/.worktrees/flag-check-refactor && ./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/roles/scoring_engine/tasks/main.yml
git commit -m "refactor(scoring): remove flag system deployment tasks

Flag checking now uses built-in DWAYNE-INATOR-5000 SSH/SMB checks
instead of custom Python scripts."
```

---

## Task 4: Delete Obsolete Flag Files

**Files:**
- Delete: `ansible/files/check_flag.py`
- Delete: `ansible/files/check_flag_count.py`
- Delete: `ansible/roles/scoring_engine/templates/flag-paths.json.j2`

**Step 1: Delete files**

```bash
cd /root/cdt-automation/.worktrees/flag-check-refactor
rm ansible/files/check_flag.py
rm ansible/files/check_flag_count.py
rm ansible/roles/scoring_engine/templates/flag-paths.json.j2
```

**Step 2: Run linter**

Run: `./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add -A
git commit -m "chore(scoring): remove obsolete flag checking scripts

- Remove check_flag.py (replaced by SSH command checks)
- Remove check_flag_count.py (no longer needed)
- Remove flag-paths.json.j2 (no longer needed)"
```

---

## Task 5: Update Documentation

**Files:**
- Modify: `scoring/README.md`

**Step 1: Update README to reflect new flag system**

Replace the flag system documentation section with updated information about using SSH/SMB checks. The key points:

1. Flag checking uses built-in DWAYNE-INATOR-5000 checks
2. Linux boxes use SSH command checks with `cat`
3. Windows boxes use SMB file checks with regex
4. Token is defined in `group_vars/scoring.yml` as `red_team_token`
5. No separate Python scripts needed

**Step 2: Commit**

```bash
git add scoring/README.md
git commit -m "docs(scoring): update flag system documentation

Reflect new approach using built-in SSH/SMB checks instead of
custom Python scripts."
```

---

## Task 6: Add Windows SMB Flag Check Example

**Files:**
- Modify: `ansible/group_vars/scoring.yml`

**Step 1: Add SMB flag check to dc01**

Find the dc01 box definition and add an SMB flag check after the existing checks:

```yaml
      # Flag check - validates Red Team flags via SMB
      - type: smb
        display: "flag"
        credlists: ["admins"]
        share: "C$"
        files:
          - name: "Users\\Public\\flag.txt"
            regex: "{{ red_team_token }}"
```

**Step 2: Run linter**

Run: `./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/group_vars/scoring.yml
git commit -m "feat(scoring): add SMB flag check example for Windows DC"
```

---

## Task 7: Final Verification

**Step 1: Run full linting**

```bash
cd /root/cdt-automation/.worktrees/flag-check-refactor
./check.sh
```
Expected: All checks passed

**Step 2: Verify git status is clean**

```bash
git status
```
Expected: Nothing to commit, working tree clean

**Step 3: Review commit history**

```bash
git log --oneline -10
```
Expected: See all implementation commits in order

---

## Summary of Changes

| File | Action | Description |
|------|--------|-------------|
| `dwayne.conf.j2` | Modified | Add SMB `share` field support |
| `scoring.yml` | Modified | Add `red_team_token`, replace cmd checks with SSH/SMB |
| `tasks/main.yml` | Modified | Remove flag system deployment tasks |
| `check_flag.py` | Deleted | No longer needed |
| `check_flag_count.py` | Deleted | No longer needed |
| `flag-paths.json.j2` | Deleted | No longer needed |
| `README.md` | Modified | Update flag system docs |
