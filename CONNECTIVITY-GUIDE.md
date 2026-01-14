# Connectivity Guide

This document explains how to connect to servers in the OpenStack cloud environment. All servers are on a private network and cannot be accessed directly from the internet. You must use one of the methods described here.

---

## Network Overview

Servers in this project are assigned IP addresses from two ranges:

**Floating IPs (Public)**: `100.65.0.0/16` (MAIN-NAT network)
- These are public IP addresses assigned to your servers
- Format: `100.65.x.x`
- Used for external access

**Internal IPs (Private)**: `10.10.10.0/24` (or your custom network)
- These are private IP addresses used for communication between servers
- Not directly accessible from outside

Even though floating IPs are "public," you cannot reach them directly from the internet. All access goes through a jump host at `ssh.cyberrange.rit.edu`.

---

## Default Credentials

All server images in this environment use the same default local account:

**Username**: `cyberrange`
**Password**: `Cyberrange123!`

This account has sudo privileges and can be used for initial access and administration.

---

## Connection Methods

### Method 1: SSH Web Client (Easiest)

A browser-based SSH client is available at:

**https://ssh.cyberrange.rit.edu**

1. Open the URL in your browser
2. Log in with your RIT credentials (if prompted)
3. Enter the floating IP of the server you want to access (e.g., `100.65.4.55`)
4. Enter username: `cyberrange`
5. Enter password: `Cyberrange123!`

This method requires no software installation and works from any computer with a web browser.

### Method 2: SSH with Jump Host (Command Line)

Use the `-J` flag to route your SSH connection through the jump host:

```bash
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<floating-ip>
```

Replace `<floating-ip>` with your server's floating IP address.

Example:
```bash
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@100.65.4.55
```

When prompted for a password, enter `Cyberrange123!`

### Method 3: SSH with ProxyJump Config (Persistent)

Add this to your `~/.ssh/config` file to avoid typing the jump host every time:

```
Host cyberrange-*
    User cyberrange
    ProxyJump sshjump@ssh.cyberrange.rit.edu

Host cyberrange-web
    HostName 100.65.4.55

Host cyberrange-db
    HostName 100.65.4.56
```

Then connect with:
```bash
ssh cyberrange-web
```

### Method 4: SOCKS5 Proxy

A SOCKS5 proxy is available for applications that support proxy connections:

**Proxy Address**: `ssh.cyberrange.rit.edu`
**Proxy Port**: `1080`
**Proxy Type**: SOCKS5

This proxy can reach any server on the MAIN-NAT network (100.65.0.0/16) if the server's security groups allow the connection.

#### Using SOCKS5 with curl

```bash
curl --socks5-hostname ssh.cyberrange.rit.edu:1080 http://100.65.4.55/
```

#### Using SOCKS5 with Firefox

1. Open Firefox Settings
2. Search for "proxy"
3. Click Settings under Network Settings
4. Select "Manual proxy configuration"
5. Enter SOCKS Host: `ssh.cyberrange.rit.edu`
6. Enter Port: `1080`
7. Select SOCKS v5
8. Check "Proxy DNS when using SOCKS v5"
9. Click OK

Now Firefox can access servers on the 100.65.x.x network directly.

#### Using SOCKS5 with RDP Clients

Some RDP clients support SOCKS5 proxies. Configure them with:
- Proxy: `ssh.cyberrange.rit.edu:1080`
- Server: The floating IP of your Windows server

---

## Connecting to Different Server Types

### Linux Servers (SSH)

```bash
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<floating-ip>
```

Password: `Cyberrange123!`

### Windows Servers (RDP)

Windows servers require Remote Desktop Protocol (RDP). Because RDP cannot use SSH jump hosts directly, you have two options:

**Option A: SSH Tunnel**

Create an SSH tunnel that forwards the RDP port:

```bash
ssh -L 3389:<floating-ip>:3389 sshjump@ssh.cyberrange.rit.edu -N
```

Keep this terminal open. Then connect your RDP client to `localhost:3389`.

**Option B: SOCKS5 Proxy**

If your RDP client supports SOCKS5 proxies, configure it to use `ssh.cyberrange.rit.edu:1080` and connect directly to the floating IP.

**Option C: Connect from Inside the Network**

SSH to a Linux server first, then use an RDP client from there:

```bash
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<linux-floating-ip>
sudo apt install freerdp2-x11
xfreerdp /v:<windows-internal-ip> /u:Administrator /p:Cyberrange123!
```

### Linux Servers (RDP via xRDP)

After running the Ansible playbooks, Linux servers have xRDP installed for remote desktop access. The desktop environment is LXQT.

Use the same connection methods as Windows (tunnel or SOCKS5 proxy), but connect to a Linux server's IP.

At the xRDP login screen:
- Select "Xorg" as the session type
- Enter your username (like `jdoe` for domain users, or `cyberrange` for local)
- Enter the password

The LXQT desktop will start after login.

### Domain Users (After Domain Setup)

After running the Ansible playbooks, domain users exist on all servers. Use them like this:

```bash
# Linux servers
ssh -J sshjump@ssh.cyberrange.rit.edu jdoe@<floating-ip>
# Password: UserPass123!

# Windows servers (RDP)
# Username: CDT\jdoe
# Password: UserPass123!
```

---

## Copying Files to Servers

### Using SCP with Jump Host

```bash
scp -J sshjump@ssh.cyberrange.rit.edu localfile.txt cyberrange@<floating-ip>:~/
```

### Copying Directories

```bash
scp -r -J sshjump@ssh.cyberrange.rit.edu ./mydirectory cyberrange@<floating-ip>:~/
```

### Using rsync (Faster for Large Transfers)

```bash
rsync -avz -e "ssh -J sshjump@ssh.cyberrange.rit.edu" ./local/ cyberrange@<floating-ip>:~/remote/
```

---

## Ansible Connectivity

Ansible is already configured to use the jump host. The configuration is in `ansible/ansible.cfg`:

```ini
[ssh_connection]
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p sshjump@ssh.cyberrange.rit.edu"
```

For Windows servers, Ansible uses WinRM with the SOCKS5 proxy:

```ini
ansible_winrm_proxy=socks5h://ssh.cyberrange.rit.edu:1080
```

You do not need to change these settings. They are already configured.

---

## Running Ansible from Inside the Network

For better reliability with Windows servers, run Ansible from a Linux server inside the cloud network.

1. Copy the ansible directory to a Linux server:
```bash
scp -r -J sshjump@ssh.cyberrange.rit.edu ansible/ cyberrange@<linux-floating-ip>:~/
```

2. SSH to that server:
```bash
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<linux-floating-ip>
```

3. Install Ansible:
```bash
sudo apt update
sudo apt install -y ansible
```

4. Run playbooks from there:
```bash
cd ~/ansible
ansible-playbook playbooks/site.yml
```

When running from inside the network, you can use internal IPs (10.10.10.x) instead of floating IPs, and you do not need the jump host.

---

## Security Groups

For connections to work, the destination server's security group must allow the traffic.

The default security group in this project (`allow_all`) permits all inbound and outbound traffic. This is appropriate for learning environments.

For your competition, you may want more restrictive security groups. Check `opentofu/security.tf` to see or modify security group rules.

Common ports to allow:
- SSH: TCP 22
- RDP: TCP 3389
- HTTP: TCP 80
- HTTPS: TCP 443
- WinRM: TCP 5985, 5986
- DNS: TCP/UDP 53
- SMB: TCP 445

---

## Troubleshooting Connections

### Cannot connect to jump host

**Symptom**: `ssh sshjump@ssh.cyberrange.rit.edu` hangs or fails

**Solutions**:
- Check your internet connection
- Try the web client at https://ssh.cyberrange.rit.edu instead
- Contact your instructor if the service is down

### Cannot connect to server through jump host

**Symptom**: Connection to jump host works, but connection to server times out

**Solutions**:
- Verify the floating IP is correct: `tofu output` in the opentofu directory
- Check if the server is running in the OpenStack dashboard
- Wait longer - Windows servers take 15-20 minutes to boot
- Check security groups allow SSH (port 22) or RDP (port 3389)

### Authentication fails

**Symptom**: Password rejected

**Solutions**:
- Verify you are using the correct password (`Cyberrange123!` for cyberrange user)
- For domain users, verify the domain is set up and try `UserPass123!`
- Try the local account (`cyberrange`) instead of domain accounts

### RDP connection fails

**Symptom**: RDP client cannot connect

**Solutions**:
- Verify SSH tunnel is running (if using tunnel method)
- Check that port 3389 is allowed in security groups
- Wait for Windows to finish booting (15-20 minutes)
- Try connecting from inside the network using a Linux server

### SOCKS5 proxy not working

**Symptom**: Applications cannot connect through the proxy

**Solutions**:
- Verify proxy settings: `ssh.cyberrange.rit.edu:1080`, SOCKS5
- Check that "Proxy DNS" is enabled in browser settings
- Verify the target server is on the MAIN-NAT network (100.65.x.x)
- Check security groups allow the traffic

---

## Quick Reference

| What | How |
|------|-----|
| SSH to Linux server | `ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<floating-ip>` |
| SSH web client | https://ssh.cyberrange.rit.edu |
| Default username | `cyberrange` |
| Default password | `Cyberrange123!` |
| Domain user password | `UserPass123!` |
| SOCKS5 proxy | `ssh.cyberrange.rit.edu:1080` |
| RDP via tunnel | `ssh -L 3389:<ip>:3389 sshjump@ssh.cyberrange.rit.edu -N` |
| Copy files | `scp -J sshjump@ssh.cyberrange.rit.edu file cyberrange@<ip>:~/` |
