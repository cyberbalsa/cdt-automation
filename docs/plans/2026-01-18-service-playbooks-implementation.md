# Service Playbooks Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create Ansible playbooks to deploy all DWAYNE-INATOR-5000 scorable services (web, ftp, mail, sql, vnc, irc).

**Architecture:** Each service gets its own playbook targeting a simple inventory group. Services use domain auth where appropriate (FTP, mail) and local accounts elsewhere (SQL, IRC). Group variables in services.yml provide defaults.

**Tech Stack:** Ansible playbooks, Jinja2 templates, systemd services

---

## Task 1: Create Services Group Variables

**Files:**
- Create: `ansible/group_vars/services.yml`

**Step 1: Create the file with all service defaults**

```yaml
---
# ==============================================================================
# SERVICE CONFIGURATION
# ==============================================================================
# Default settings for optional CTF services.
# These playbooks install services that DWAYNE-INATOR-5000 can score.
#
# USAGE:
# 1. Add hosts to inventory groups: [web], [ftp], [mail], [sql], [vnc], [irc]
# 2. Run: ansible-playbook playbooks/setup-<service>.yml
# ==============================================================================

# ------------------------------------------------------------------------------
# WEB SERVER (Apache)
# ------------------------------------------------------------------------------
web_document_root: "/var/www/html"
web_server_name: "{{ inventory_hostname }}.{{ domain_name }}"
web_enable_ssl: true

# ------------------------------------------------------------------------------
# FTP SERVER (vsftpd)
# ------------------------------------------------------------------------------
ftp_allow_anonymous: false
ftp_local_enable: true
ftp_write_enable: true
ftp_chroot_local_user: false

# ------------------------------------------------------------------------------
# MAIL SERVER (Postfix + Dovecot)
# ------------------------------------------------------------------------------
mail_domain: "{{ domain_name }}"
mail_hostname: "mail.{{ domain_name }}"

# ------------------------------------------------------------------------------
# SQL SERVER (MariaDB)
# ------------------------------------------------------------------------------
sql_bind_address: "0.0.0.0"
sql_scoring_db: "scoring_test"
sql_scoring_user: "scoring"
sql_scoring_password: "ScoringDB123!"

# ------------------------------------------------------------------------------
# VNC SERVER (x11vnc)
# ------------------------------------------------------------------------------
vnc_password: "VncPass123!"
vnc_display: ":0"
vnc_port: 5900

# ------------------------------------------------------------------------------
# IRC SERVER (ngircd)
# ------------------------------------------------------------------------------
irc_server_name: "irc.{{ domain_name }}"
irc_network_name: "CTFNet"
irc_motd: "Welcome to the CTF IRC server!"
irc_channel: "#ctf"
irc_oper_name: "admin"
irc_oper_password: "IrcAdmin123!"
```

**Step 2: Run linter**

Run: `./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/group_vars/services.yml
git commit -m "feat(ansible): add service configuration defaults"
```

---

## Task 2: Create Web Server Playbook (Apache)

**Files:**
- Create: `ansible/playbooks/setup-web.yml`

**Step 1: Create the playbook**

```yaml
---
# ==============================================================================
# WEB SERVER SETUP (Apache)
# ==============================================================================
# Installs and configures Apache web server for CTF scoring.
#
# INVENTORY GROUP: [web]
# SCORED BY: type: web (HTTP status checks)
#
# EXAMPLE SCORING CHECK:
#   - type: web
#     urls:
#       - path: "/"
#         status: 200
# ==============================================================================

- name: Setup Apache Web Server
  hosts: web
  become: yes
  tasks:
    - name: Install Apache
      ansible.builtin.apt:
        name:
          - apache2
          - openssl
        state: present
        update_cache: yes

    - name: Enable Apache modules
      community.general.apache2_module:
        name: "{{ item }}"
        state: present
      loop:
        - ssl
        - rewrite
      notify: Restart Apache

    - name: Create document root
      ansible.builtin.file:
        path: "{{ web_document_root }}"
        state: directory
        owner: www-data
        group: www-data
        mode: "0755"

    - name: Create test index page
      ansible.builtin.copy:
        dest: "{{ web_document_root }}/index.html"
        content: |
          <!DOCTYPE html>
          <html>
          <head><title>{{ inventory_hostname }}</title></head>
          <body>
          <h1>Welcome to {{ inventory_hostname }}</h1>
          <p>This server is operational.</p>
          </body>
          </html>
        owner: www-data
        group: www-data
        mode: "0644"

    - name: Generate self-signed SSL certificate
      ansible.builtin.command:
        cmd: >
          openssl req -x509 -nodes -days 365 -newkey rsa:2048
          -keyout /etc/ssl/private/apache-selfsigned.key
          -out /etc/ssl/certs/apache-selfsigned.crt
          -subj "/CN={{ web_server_name }}"
        creates: /etc/ssl/certs/apache-selfsigned.crt
      when: web_enable_ssl | default(true)

    - name: Enable default SSL site
      ansible.builtin.command:
        cmd: a2ensite default-ssl
        creates: /etc/apache2/sites-enabled/default-ssl.conf
      when: web_enable_ssl | default(true)
      notify: Restart Apache

    - name: Ensure Apache is running
      ansible.builtin.systemd:
        name: apache2
        enabled: yes
        state: started

  handlers:
    - name: Restart Apache
      ansible.builtin.systemd:
        name: apache2
        state: restarted
```

**Step 2: Run linter**

Run: `./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/playbooks/setup-web.yml
git commit -m "feat(ansible): add Apache web server playbook"
```

---

## Task 3: Create FTP Server Playbook (vsftpd)

**Files:**
- Create: `ansible/playbooks/setup-ftp.yml`

**Step 1: Create the playbook**

```yaml
---
# ==============================================================================
# FTP SERVER SETUP (vsftpd)
# ==============================================================================
# Installs and configures vsftpd for CTF scoring.
# Uses domain authentication via PAM/SSSD.
#
# INVENTORY GROUP: [ftp]
# SCORED BY: type: ftp (login and file operations)
#
# EXAMPLE SCORING CHECK:
#   - type: ftp
#     credlists: ["domain_users"]
# ==============================================================================

- name: Setup vsftpd FTP Server
  hosts: ftp
  become: yes
  tasks:
    - name: Install vsftpd
      ansible.builtin.apt:
        name: vsftpd
        state: present
        update_cache: yes

    - name: Configure vsftpd
      ansible.builtin.copy:
        dest: /etc/vsftpd.conf
        content: |
          # vsftpd configuration for CTF
          listen=YES
          listen_ipv6=NO

          # Authentication
          anonymous_enable={{ 'YES' if ftp_allow_anonymous else 'NO' }}
          local_enable={{ 'YES' if ftp_local_enable else 'NO' }}

          # Permissions
          write_enable={{ 'YES' if ftp_write_enable else 'NO' }}
          local_umask=022

          # Chroot settings
          chroot_local_user={{ 'YES' if ftp_chroot_local_user else 'NO' }}
          allow_writeable_chroot=YES

          # PAM authentication (uses SSSD for domain users)
          pam_service_name=vsftpd

          # Logging
          xferlog_enable=YES
          xferlog_std_format=YES

          # Security
          ssl_enable=NO

          # Passive mode (useful for firewalled environments)
          pasv_enable=YES
          pasv_min_port=30000
          pasv_max_port=30100
        owner: root
        group: root
        mode: "0644"
      notify: Restart vsftpd

    - name: Ensure vsftpd is running
      ansible.builtin.systemd:
        name: vsftpd
        enabled: yes
        state: started

  handlers:
    - name: Restart vsftpd
      ansible.builtin.systemd:
        name: vsftpd
        state: restarted
```

**Step 2: Run linter**

Run: `./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/playbooks/setup-ftp.yml
git commit -m "feat(ansible): add vsftpd FTP server playbook"
```

---

## Task 4: Create Mail Server Playbook (Postfix + Dovecot)

**Files:**
- Create: `ansible/playbooks/setup-mail.yml`

**Step 1: Create the playbook**

```yaml
---
# ==============================================================================
# MAIL SERVER SETUP (Postfix + Dovecot)
# ==============================================================================
# Installs Postfix (SMTP) and Dovecot (IMAP) for CTF scoring.
# Uses domain authentication via PAM/SSSD.
#
# INVENTORY GROUP: [mail]
# SCORED BY: type: smtp, type: imap
#
# EXAMPLE SCORING CHECKS:
#   - type: smtp
#     sender: "scoring@CDT.local"
#     receiver: "jdoe@CDT.local"
#   - type: imap
#     credlists: ["domain_users"]
# ==============================================================================

- name: Setup Postfix and Dovecot Mail Server
  hosts: mail
  become: yes
  tasks:
    # --------------------------------------------------------------------------
    # Postfix (SMTP)
    # --------------------------------------------------------------------------
    - name: Set Postfix preseed values
      ansible.builtin.debconf:
        name: postfix
        question: "{{ item.question }}"
        value: "{{ item.value }}"
        vtype: "{{ item.vtype }}"
      loop:
        - { question: "postfix/main_mailer_type", value: "Internet Site", vtype: "select" }
        - { question: "postfix/mailname", value: "{{ mail_hostname }}", vtype: "string" }

    - name: Install mail packages
      ansible.builtin.apt:
        name:
          - postfix
          - dovecot-imapd
          - mailutils
        state: present
        update_cache: yes

    - name: Configure Postfix main.cf
      ansible.builtin.lineinfile:
        path: /etc/postfix/main.cf
        regexp: "^{{ item.key }}\\s*="
        line: "{{ item.key }} = {{ item.value }}"
      loop:
        - { key: "myhostname", value: "{{ mail_hostname }}" }
        - { key: "mydomain", value: "{{ mail_domain }}" }
        - { key: "myorigin", value: "$mydomain" }
        - { key: "mydestination", value: "$myhostname, localhost.$mydomain, localhost, $mydomain" }
        - { key: "inet_interfaces", value: "all" }
        - { key: "home_mailbox", value: "Maildir/" }
      notify: Restart Postfix

    # --------------------------------------------------------------------------
    # Dovecot (IMAP)
    # --------------------------------------------------------------------------
    - name: Configure Dovecot mail location
      ansible.builtin.lineinfile:
        path: /etc/dovecot/conf.d/10-mail.conf
        regexp: "^mail_location\\s*="
        line: "mail_location = maildir:~/Maildir"
      notify: Restart Dovecot

    - name: Configure Dovecot plaintext auth
      ansible.builtin.lineinfile:
        path: /etc/dovecot/conf.d/10-auth.conf
        regexp: "^disable_plaintext_auth\\s*="
        line: "disable_plaintext_auth = no"
      notify: Restart Dovecot

    - name: Ensure mail services are running
      ansible.builtin.systemd:
        name: "{{ item }}"
        enabled: yes
        state: started
      loop:
        - postfix
        - dovecot

  handlers:
    - name: Restart Postfix
      ansible.builtin.systemd:
        name: postfix
        state: restarted

    - name: Restart Dovecot
      ansible.builtin.systemd:
        name: dovecot
        state: restarted
```

**Step 2: Run linter**

Run: `./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/playbooks/setup-mail.yml
git commit -m "feat(ansible): add Postfix/Dovecot mail server playbook"
```

---

## Task 5: Create SQL Server Playbook (MariaDB)

**Files:**
- Create: `ansible/playbooks/setup-sql.yml`

**Step 1: Create the playbook**

```yaml
---
# ==============================================================================
# SQL SERVER SETUP (MariaDB)
# ==============================================================================
# Installs and configures MariaDB for CTF scoring.
# Creates a test database with local user for scoring checks.
#
# INVENTORY GROUP: [sql]
# SCORED BY: type: sql (database queries)
#
# EXAMPLE SCORING CHECK:
#   - type: sql
#     kind: mysql
#     queries:
#       - database: "scoring_test"
#         databaseexists: true
# ==============================================================================

- name: Setup MariaDB SQL Server
  hosts: sql
  become: yes
  tasks:
    - name: Install MariaDB
      ansible.builtin.apt:
        name:
          - mariadb-server
          - python3-pymysql
        state: present
        update_cache: yes

    - name: Configure MariaDB to listen on all interfaces
      ansible.builtin.lineinfile:
        path: /etc/mysql/mariadb.conf.d/50-server.cnf
        regexp: "^bind-address"
        line: "bind-address = {{ sql_bind_address }}"
      notify: Restart MariaDB

    - name: Ensure MariaDB is running
      ansible.builtin.systemd:
        name: mariadb
        enabled: yes
        state: started

    - name: Create scoring test database
      community.mysql.mysql_db:
        name: "{{ sql_scoring_db }}"
        state: present
        login_unix_socket: /var/run/mysqld/mysqld.sock

    - name: Create scoring user
      community.mysql.mysql_user:
        name: "{{ sql_scoring_user }}"
        password: "{{ sql_scoring_password }}"
        host: "%"
        priv: "{{ sql_scoring_db }}.*:ALL"
        state: present
        login_unix_socket: /var/run/mysqld/mysqld.sock

    - name: Create test table
      community.mysql.mysql_query:
        login_unix_socket: /var/run/mysqld/mysqld.sock
        login_db: "{{ sql_scoring_db }}"
        query: |
          CREATE TABLE IF NOT EXISTS status (
            id INT PRIMARY KEY AUTO_INCREMENT,
            message VARCHAR(255),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          );
          INSERT INTO status (message) VALUES ('Service operational')
          ON DUPLICATE KEY UPDATE message = 'Service operational';

  handlers:
    - name: Restart MariaDB
      ansible.builtin.systemd:
        name: mariadb
        state: restarted
```

**Step 2: Run linter**

Run: `./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/playbooks/setup-sql.yml
git commit -m "feat(ansible): add MariaDB SQL server playbook"
```

---

## Task 6: Create VNC Server Playbook (x11vnc)

**Files:**
- Create: `ansible/playbooks/setup-vnc.yml`

**Step 1: Create the playbook**

```yaml
---
# ==============================================================================
# VNC SERVER SETUP (x11vnc)
# ==============================================================================
# Installs x11vnc to share the existing X display.
# Requires desktop environment (run setup-rdp-linux.yml first).
#
# INVENTORY GROUP: [vnc]
# SCORED BY: type: vnc (VNC connection)
#
# EXAMPLE SCORING CHECK:
#   - type: vnc
#     port: 5900
# ==============================================================================

- name: Setup x11vnc VNC Server
  hosts: vnc
  become: yes
  tasks:
    - name: Install x11vnc
      ansible.builtin.apt:
        name: x11vnc
        state: present
        update_cache: yes

    - name: Create VNC password file
      ansible.builtin.shell: |
        x11vnc -storepasswd "{{ vnc_password }}" /etc/x11vnc.pass
      args:
        creates: /etc/x11vnc.pass

    - name: Set password file permissions
      ansible.builtin.file:
        path: /etc/x11vnc.pass
        owner: root
        group: root
        mode: "0644"

    - name: Create x11vnc systemd service
      ansible.builtin.copy:
        dest: /etc/systemd/system/x11vnc.service
        content: |
          [Unit]
          Description=x11vnc VNC Server
          After=display-manager.service
          Requires=display-manager.service

          [Service]
          Type=simple
          ExecStart=/usr/bin/x11vnc -display {{ vnc_display }} -auth guess -forever -loop -noxdamage -repeat -rfbauth /etc/x11vnc.pass -rfbport {{ vnc_port }} -shared
          Restart=on-failure
          RestartSec=5

          [Install]
          WantedBy=multi-user.target
        owner: root
        group: root
        mode: "0644"
      notify: Reload systemd

    - name: Enable and start x11vnc
      ansible.builtin.systemd:
        name: x11vnc
        enabled: yes
        state: started
        daemon_reload: yes

  handlers:
    - name: Reload systemd
      ansible.builtin.systemd:
        daemon_reload: yes
```

**Step 2: Run linter**

Run: `./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/playbooks/setup-vnc.yml
git commit -m "feat(ansible): add x11vnc VNC server playbook"
```

---

## Task 7: Create IRC Server Playbook (ngircd)

**Files:**
- Create: `ansible/playbooks/setup-irc.yml`

**Step 1: Create the playbook**

```yaml
---
# ==============================================================================
# IRC SERVER SETUP (ngircd)
# ==============================================================================
# Installs and configures ngircd IRC server for CTF scoring.
# Minimal configuration with one channel.
#
# INVENTORY GROUP: [irc]
# SCORED BY: type: irc (IRC connection)
#
# EXAMPLE SCORING CHECK:
#   - type: irc
#     port: 6667
# ==============================================================================

- name: Setup ngircd IRC Server
  hosts: irc
  become: yes
  tasks:
    - name: Install ngircd
      ansible.builtin.apt:
        name: ngircd
        state: present
        update_cache: yes

    - name: Configure ngircd
      ansible.builtin.copy:
        dest: /etc/ngircd/ngircd.conf
        content: |
          # ngircd configuration for CTF

          [Global]
          Name = {{ irc_server_name }}
          Info = CTF IRC Server
          Listen = 0.0.0.0
          MotdFile = /etc/ngircd/ngircd.motd

          [Limits]
          MaxConnections = 100
          MaxJoins = 10

          [Options]
          AllowRemoteOper = no
          PAM = no

          [Operator]
          Name = {{ irc_oper_name }}
          Password = {{ irc_oper_password }}

          [Channel]
          Name = {{ irc_channel }}
          Topic = Welcome to the CTF!
          Modes = tn
        owner: root
        group: root
        mode: "0644"
      notify: Restart ngircd

    - name: Create MOTD file
      ansible.builtin.copy:
        dest: /etc/ngircd/ngircd.motd
        content: |
          {{ irc_motd }}

          Network: {{ irc_network_name }}
          Channel: {{ irc_channel }}
        owner: root
        group: root
        mode: "0644"
      notify: Restart ngircd

    - name: Ensure ngircd is running
      ansible.builtin.systemd:
        name: ngircd
        enabled: yes
        state: started

  handlers:
    - name: Restart ngircd
      ansible.builtin.systemd:
        name: ngircd
        state: restarted
```

**Step 2: Run linter**

Run: `./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/playbooks/setup-irc.yml
git commit -m "feat(ansible): add ngircd IRC server playbook"
```

---

## Task 8: Update site.yml with Service Playbooks

**Files:**
- Modify: `ansible/playbooks/site.yml`

**Step 1: Add service playbook imports after domain users**

Find the domain users import and add the service playbooks after it, before RDP setup:

```yaml
# Service playbooks (optional - only run if hosts in groups)
- import_playbook: setup-web.yml
- import_playbook: setup-ftp.yml
- import_playbook: setup-mail.yml
- import_playbook: setup-sql.yml
- import_playbook: setup-vnc.yml
- import_playbook: setup-irc.yml
```

**Step 2: Run linter**

Run: `./check.sh`
Expected: All checks passed

**Step 3: Commit**

```bash
git add ansible/playbooks/site.yml
git commit -m "feat(ansible): add service playbooks to site.yml"
```

---

## Task 9: Final Verification

**Step 1: Run full linting**

```bash
./check.sh
```
Expected: All checks passed

**Step 2: Verify git status**

```bash
git status
```
Expected: Working tree clean

**Step 3: List new playbooks**

```bash
ls -la ansible/playbooks/setup-*.yml
```
Expected: See all 6 new service playbooks

---

## Summary of Changes

| File | Action | Description |
|------|--------|-------------|
| `group_vars/services.yml` | Create | Service configuration defaults |
| `playbooks/setup-web.yml` | Create | Apache web server |
| `playbooks/setup-ftp.yml` | Create | vsftpd FTP server |
| `playbooks/setup-mail.yml` | Create | Postfix + Dovecot mail |
| `playbooks/setup-sql.yml` | Create | MariaDB database |
| `playbooks/setup-vnc.yml` | Create | x11vnc VNC server |
| `playbooks/setup-irc.yml` | Create | ngircd IRC server |
| `playbooks/site.yml` | Modify | Import new playbooks |
