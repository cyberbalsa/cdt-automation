# Service Playbooks Design

**Date:** 2026-01-18
**Status:** Approved

## Overview

Add Ansible playbooks to deploy all services that DWAYNE-INATOR-5000 can score. Playbooks are flexible - they work on any host assigned via inventory groups.

## Services

| Playbook | Service | Software | Auth | Port(s) | Inventory Group |
|----------|---------|----------|------|---------|-----------------|
| `setup-web.yml` | HTTP/HTTPS | Apache | N/A | 80, 443 | `[web]` |
| `setup-ftp.yml` | FTP | vsftpd | Domain | 21 | `[ftp]` |
| `setup-mail.yml` | SMTP+IMAP | Postfix+Dovecot | Domain | 25, 143 | `[mail]` |
| `setup-sql.yml` | MySQL | MariaDB | Local | 3306 | `[sql]` |
| `setup-vnc.yml` | VNC | x11vnc | Desktop | 5900 | `[vnc]` |
| `setup-irc.yml` | IRC | ngircd | Local | 6667 | `[irc]` |

## Inventory Example

```ini
[web]
webserver

[ftp]
webserver

[mail]
blue-linux-2

[sql]
blue-linux-2

[vnc]
blue-linux-3

[irc]
blue-linux-3
```

## Service Configurations

### Web (Apache)

- Package: `apache2`
- Enable mod_ssl for HTTPS
- Default site serves `/var/www/html`
- Creates test `index.html` with hostname
- Self-signed certificate for HTTPS
- Scoring check: `type: web` with `path: "/"`, `status: 200`

### FTP (vsftpd)

- Package: `vsftpd`
- Domain users authenticate via PAM/SSSD
- Users access their home directories
- Anonymous access disabled
- Scoring check: `type: ftp` with `credlists: ["domain_users"]`

### Mail (Postfix + Dovecot)

- Packages: `postfix`, `dovecot-imapd`
- Postfix for SMTP (sending)
- Dovecot for IMAP (receiving)
- Uses `CDT.local` domain from existing config
- Domain users can send/receive mail
- Scoring checks: `type: smtp`, `type: imap`

### SQL (MariaDB)

- Package: `mariadb-server`
- Create scoring test database and local user
- Bind to all interfaces for remote scoring
- Scoring check: `type: sql`, `kind: mysql` with query

### VNC (x11vnc)

- Package: `x11vnc`
- Requires existing desktop (LXQT from setup-rdp-linux.yml)
- Shares active X display session
- Systemd service for auto-start
- Password file at `/etc/x11vnc.pass`
- Scoring check: `type: vnc`, `port: 5900`

### IRC (ngircd)

- Package: `ngircd`
- Minimal config: server name, network, one channel
- No authentication (open server)
- Scoring check: `type: irc`, `port: 6667`

## Group Variables

New file: `ansible/group_vars/services.yml`

```yaml
# Web
web_document_root: "/var/www/html"

# FTP
ftp_allow_anonymous: false

# Mail
mail_domain: "{{ domain_name }}"

# SQL
sql_scoring_db: "scoring_test"
sql_scoring_user: "scoring"
sql_scoring_password: "ScoringDB123!"

# VNC
vnc_password: "VncPass123!"

# IRC
irc_server_name: "irc.{{ domain_name }}"
irc_channel: "#ctf"
```

## Integration

### site.yml Execution Order

1. Validate Inventory
2. Setup Domain Controller
3. Join Windows Members
4. Activate Windows
5. Join Linux Members
6. Create Domain Users
7. **Setup Web** (new)
8. **Setup FTP** (new)
9. **Setup Mail** (new)
10. **Setup SQL** (new)
11. **Setup VNC** (new)
12. **Setup IRC** (new)
13. Setup RDP Linux
14. Setup RDP Windows
15. Setup Scoring Engine

### Scoring Configuration Examples

```yaml
scoring_boxes:
  - name: "webserver"
    ip: "10.10.10.31"
    checks:
      - type: ping
      - type: ssh
        credlists: ["linux_users"]
      - type: web
        urls:
          - path: "/"
            status: 200
      - type: ftp
        credlists: ["domain_users"]

  - name: "mailserver"
    ip: "10.10.10.32"
    checks:
      - type: ping
      - type: ssh
        credlists: ["linux_users"]
      - type: smtp
        sender: "scoring@CDT.local"
        receiver: "jdoe@CDT.local"
      - type: imap
        credlists: ["domain_users"]

  - name: "dbserver"
    ip: "10.10.10.33"
    checks:
      - type: ping
      - type: ssh
        credlists: ["linux_users"]
      - type: sql
        kind: mysql
        queries:
          - database: "scoring_test"
            databaseexists: true

  - name: "miscserver"
    ip: "10.10.10.34"
    checks:
      - type: ping
      - type: ssh
        credlists: ["linux_users"]
      - type: vnc
        port: 5900
      - type: irc
        port: 6667
```

## Implementation Tasks

1. Create `ansible/group_vars/services.yml` with default variables
2. Create `ansible/playbooks/setup-web.yml` - Apache installation
3. Create `ansible/playbooks/setup-ftp.yml` - vsftpd with domain auth
4. Create `ansible/playbooks/setup-mail.yml` - Postfix + Dovecot
5. Create `ansible/playbooks/setup-sql.yml` - MariaDB setup
6. Create `ansible/playbooks/setup-vnc.yml` - x11vnc with systemd
7. Create `ansible/playbooks/setup-irc.yml` - ngircd minimal config
8. Update `ansible/playbooks/site.yml` - Add new playbook imports
9. Update `ansible/group_vars/scoring.yml` - Add example service checks
10. Update documentation
