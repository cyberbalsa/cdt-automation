# Deployment Guide

This guide walks you through deploying competition infrastructure from scratch. It assumes no prior experience with command-line tools, OpenTofu, or Ansible.

Work through each section in order. Do not skip steps.

---

## Table of Contents

1. [Before You Begin](#before-you-begin)
2. [Understanding the Basics](#understanding-the-basics)
3. [Install Required Software](#install-required-software)
4. [Set Up SSH Keys](#set-up-ssh-keys)
5. [Get Your OpenStack Project IDs](#get-your-openstack-project-ids)
6. [Create Application Credentials](#create-application-credentials)
7. [Clone and Configure the Repository](#clone-and-configure-the-repository)
8. [Deploy Infrastructure](#deploy-infrastructure)
9. [Generate Ansible Inventory](#generate-ansible-inventory)
10. [Configure Servers with Ansible](#configure-servers-with-ansible)
11. [Verify Everything Works](#verify-everything-works)
12. [What is Next](#what-is-next)

---

## Before You Begin

### What You Will Need

- A computer (Windows, macOS, or Linux)
- Internet connection
- Approximately 2 hours of uninterrupted time
- Three OpenStack project names from your instructor

### What You Will Receive From Your Instructor

Your instructor will give you the names of three OpenStack projects:

| Project | Purpose |
|---------|---------|
| Main project | Your Grey Team project. Contains the network and scoring servers. |
| Blue project | Blue Team project. Contains Windows and Linux servers they will defend. |
| Red project | Red Team project. Contains Kali attack machines. |

Write down these project names. You will need them later.

### What You Will Build

By the end of this guide, you will have deployed:

```
                        INTERNET
                            |
                       [MAIN-NAT]         External network
                            |
                      [cdt_router]        Router (your main project)
                            |
                      [cdt_subnet]        10.10.10.0/24 (shared network)
                            |
       +--------------------+--------------------+--------------------+
       |                    |                    |                    |
  [Scoring]            [Blue Team]          [Blue Team]          [Red Team]
  10.10.10.1x          Windows              Linux                Kali
  (Grey Team)          10.10.10.2x          10.10.10.3x          10.10.10.4x
```

All servers will be on the same network but owned by different OpenStack projects. This allows your Grey Team to control the network while Blue Team and Red Team only have access to their own servers.

---

## Understanding the Basics

### What is a Terminal?

A terminal (also called command line, shell, or console) is a text-based interface for controlling your computer. Instead of clicking buttons and icons, you type commands.

**Opening a terminal:**

**On macOS:**
1. Press Command + Space to open Spotlight
2. Type "Terminal" and press Enter

**On Windows:**
1. Press Windows key
2. Type "PowerShell" and click "Windows PowerShell"
3. Alternatively, install Windows Subsystem for Linux (WSL) for a Linux-like experience

**On Linux:**
1. Press Ctrl + Alt + T
2. Or search for "Terminal" in your applications menu

### Running Your First Command

Once you have a terminal open, type the following and press Enter:

```bash
echo "Hello, World!"
```

You should see `Hello, World!` printed on the next line. This is how commands work: you type a command, press Enter, and the computer responds.

### What Are These Tools?

This project uses several tools. Here is what each one does:

**Git** - A version control system. It tracks changes to files and lets you download code from the internet. You will use it to download this project.

**OpenTofu** - An infrastructure-as-code tool. Instead of clicking through a web interface to create servers, you write configuration files that describe what you want. OpenTofu reads these files and creates the servers for you.

**Ansible** - A configuration management tool. After servers exist, Ansible connects to them and runs commands to install software and configure settings. You write playbooks that describe the desired state, and Ansible makes it happen.

**Python** - A programming language. This project includes Python scripts that help connect OpenTofu and Ansible together.

---

## Install Required Software

Install each tool and verify it works before moving to the next one.

### Install Git

**On macOS:**
```bash
# Check if already installed
git --version

# If not installed, macOS will prompt you to install Xcode Command Line Tools
# Click "Install" when prompted
```

**On Windows (PowerShell):**
1. Download Git from https://git-scm.com/download/win
2. Run the installer, accepting all defaults
3. Close and reopen PowerShell
4. Verify: `git --version`

**On Ubuntu/Debian Linux:**
```bash
sudo apt update
sudo apt install -y git
git --version
```

**Verification:** You should see a version number like `git version 2.39.0`. The exact number does not matter.

### Install OpenTofu

**On macOS:**
```bash
brew install opentofu
tofu version
```

If you do not have Homebrew, install it first from https://brew.sh

**On Windows:**
1. Download the Windows ZIP from https://opentofu.org/docs/intro/install/
2. Extract the ZIP file
3. Move `tofu.exe` to a folder in your PATH, or add its location to PATH
4. Open a new PowerShell and verify: `tofu version`

**On Ubuntu/Debian Linux:**
```bash
# Add the OpenTofu repository
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sudo bash -s -- --install-method deb

# Verify installation
tofu version
```

**Verification:** You should see version information like `OpenTofu v1.6.0`. The exact version does not matter.

### Install Ansible

**On macOS:**
```bash
brew install ansible
ansible --version
```

**On Windows:**

Ansible does not run natively on Windows. You have two options:

Option A - Use WSL (Recommended):
1. Open PowerShell as Administrator
2. Run: `wsl --install`
3. Restart your computer
4. Open "Ubuntu" from the Start menu
5. Follow the Ubuntu/Debian instructions below

Option B - Run Ansible from inside the cloud:
Skip installing Ansible locally. You will install it on a Linux server in the cloud and run it from there. This guide covers this approach in the Ansible section.

**On Ubuntu/Debian Linux:**
```bash
sudo apt update
sudo apt install -y ansible
ansible --version
```

**Verification:** You should see version information including `ansible [core 2.x.x]`.

### Install Python 3

Python 3 is usually pre-installed on macOS and Linux.

**Check if installed:**
```bash
python3 --version
```

**On macOS (if not installed):**
```bash
brew install python3
```

**On Windows:**
1. Download from https://www.python.org/downloads/
2. Run the installer
3. IMPORTANT: Check "Add Python to PATH" during installation
4. Verify in a new PowerShell: `python --version` or `python3 --version`

**On Ubuntu/Debian Linux (if not installed):**
```bash
sudo apt update
sudo apt install -y python3
```

**Verification:** You should see a version number like `Python 3.11.0`. Any version 3.8 or higher works.

### Troubleshooting Installation Issues

**"command not found" error:**
- Close your terminal and open a new one
- The tool may not be in your PATH. Check installation instructions for your operating system.

**Permission denied:**
- On Linux/macOS, prefix the command with `sudo` (e.g., `sudo apt install git`)
- On Windows, run PowerShell as Administrator

**macOS says app is from unidentified developer:**
- Go to System Preferences, then Security and Privacy
- Click "Allow Anyway" for the blocked application

---

## Set Up SSH Keys

SSH keys let you connect to servers securely without typing passwords. OpenStack and your servers need these keys.

### What is an SSH Key?

An SSH key is a pair of files:
- **Private key** (`~/.ssh/id_rsa`): Secret. Never share this file.
- **Public key** (`~/.ssh/id_rsa.pub`): Safe to share. You upload this to OpenStack.

When you connect to a server, the server checks if your private key matches the public key you uploaded. If they match, you get access.

### Check If You Already Have a Key

```bash
ls ~/.ssh/id_rsa*
```

If you see files like `id_rsa` and `id_rsa.pub`, you already have a key. Skip to "Upload Your Key to OpenStack."

If you see "No such file or directory," you need to create a key.

### Create an SSH Key

Run this command:

```bash
ssh-keygen -t rsa -b 4096
```

The command will ask several questions:

```
Enter file in which to save the key (/home/you/.ssh/id_rsa):
```
Press Enter to accept the default location.

```
Enter passphrase (empty for no passphrase):
```
Press Enter for no passphrase (or enter one if you want extra security).

```
Enter same passphrase again:
```
Press Enter again.

You should see output confirming the key was created.

### Upload Your Key to OpenStack

1. Open your web browser and go to https://openstack.cyberrange.rit.edu

2. Log in with your credentials

3. In the left sidebar, click **Compute**, then **Key Pairs**

4. Click **Import Public Key** (top right)

5. Fill in the form:
   - **Key Pair Name**: Enter a memorable name like `my-laptop-key` (write this down, you need it later)
   - **Key Type**: Select "SSH Key"
   - **Public Key**: Paste the contents of your public key file

6. To get your public key contents, run this in your terminal:
   ```bash
   cat ~/.ssh/id_rsa.pub
   ```
   Copy the entire output (starts with `ssh-rsa` and ends with something like `user@computer`).

7. Paste into the Public Key field and click **Import Public Key**

**Write down your key pair name:** ________________

You will enter this name in a configuration file later.

---

## Get Your OpenStack Project IDs

OpenTofu needs the unique IDs of your three projects, not just their names.

### Find Your Project IDs

1. Log into OpenStack at https://openstack.cyberrange.rit.edu

2. In the top left, you should see a dropdown showing your current project name. Click it to see all projects you have access to.

3. For each of your three projects (main, blue, red), do the following:

   a. Select the project from the dropdown

   b. In the left sidebar, click **Identity**, then **Projects**

   c. Find your project in the list

   d. The **Project ID** column shows a long string of letters and numbers (like `04846fb2e027424d8898953062787b16`)

   e. Click the ID to copy it, or write it down

4. Record all three IDs:

| Project | Name | ID |
|---------|------|-----|
| Main | ________________ | ________________________________ |
| Blue | ________________ | ________________________________ |
| Red | ________________ | ________________________________ |

**Important:** These IDs are case-sensitive. Copy them exactly.

---

## Create Application Credentials

Application credentials let OpenTofu authenticate to OpenStack without using your personal password.

### Create the Credential

1. In OpenStack, make sure you have your **main project** selected (check the dropdown in the top left)

2. In the left sidebar, click **Identity**, then **Application Credentials**

3. Click **Create Application Credential**

4. Fill in the form:
   - **Name**: Enter something memorable like `grey-team-automation`
   - **Description**: Optional, like "For OpenTofu deployment"
   - Leave other fields as defaults

5. Click **Create Application Credential**

6. **IMPORTANT:** On the success screen, click **Download openrc file**
   - Save this file somewhere you can find it
   - The secret is only shown once. If you lose it, you must create a new credential.

7. Click **Close**

### Move the Credentials File

Move the downloaded file to your project directory. The file name looks like `app-cred-YOUR-NAME-openrc.sh`.

You will do this after cloning the repository in the next section.

---

## Clone and Configure the Repository

### Clone the Repository

Open your terminal and navigate to where you want to store the project:

```bash
# Go to your home directory
cd ~

# Clone the repository (replace with actual URL)
git clone <your-repo-url>

# Enter the project directory
cd cdt-automation
```

If you see "fatal: destination path already exists," the folder already exists. Either delete it and try again, or use the existing folder.

### Move Your Credentials File

Move the credentials file you downloaded earlier into this directory:

```bash
# Example - adjust the path to where you saved the file
mv ~/Downloads/app-cred-*-openrc.sh .
```

### Run the Setup Script

The setup script checks your environment and renames your credentials file:

```bash
./quick-start.sh
```

If you see "Permission denied," make the script executable first:

```bash
chmod +x quick-start.sh
./quick-start.sh
```

The script will:
- Check that required tools are installed
- Find your credentials file and rename it to `app-cred-openrc.sh`
- Initialize OpenTofu

### Configure Your Project IDs and SSH Key

Open the variables file in a text editor:

```bash
# Using nano (simple editor)
nano opentofu/variables.tf

# Or using VS Code if installed
code opentofu/variables.tf
```

Find these sections and update them with your values:

**SSH Key Name:**
```hcl
variable "keypair_name" {
  description = "Name of SSH keypair to use"
  type        = string
  default     = "my-laptop-key"  # <-- Change this to YOUR key pair name
}
```

**Project IDs:**
```hcl
variable "main_project_id" {
  description = "OpenStack project ID for main/grey team"
  type        = string
  default     = "your-main-project-id-here"  # <-- Paste your main project ID
}

variable "blue_project_id" {
  description = "OpenStack project ID for blue team"
  type        = string
  default     = "your-blue-project-id-here"  # <-- Paste your blue project ID
}

variable "red_project_id" {
  description = "OpenStack project ID for red team"
  type        = string
  default     = "your-red-project-id-here"  # <-- Paste your red project ID
}
```

**Save the file:**
- In nano: Press Ctrl+O, then Enter, then Ctrl+X
- In VS Code: Press Ctrl+S (or Cmd+S on Mac)

---

## Deploy Infrastructure

Now you will create the servers, networks, and other resources.

### Load Your Credentials

Every time you open a new terminal, you must load your credentials before running OpenTofu commands:

```bash
source app-cred-openrc.sh
```

This command sets environment variables that OpenTofu uses to authenticate. You will not see any output if it works correctly.

### Preview the Deployment

Navigate to the OpenTofu directory and preview what will be created:

```bash
cd opentofu
tofu plan
```

**Understanding the output:**

The `tofu plan` command shows what OpenTofu will create without actually creating it. You will see output like:

```
Terraform will perform the following actions:

  # openstack_compute_instance_v2.blue_linux[0] will be created
  + resource "openstack_compute_instance_v2" "blue_linux" {
      + name        = "webserver"
      + flavor_name = "medium"
      ...
    }

Plan: 15 to add, 0 to change, 0 to destroy.
```

This tells you:
- What resources will be created (networks, servers, etc.)
- How many total resources (`15 to add` means 15 new things)
- Nothing will be changed or destroyed (this is a fresh deployment)

**If you see errors:**
- "authentication required" or "unauthorized": Run `source app-cred-openrc.sh` again
- "could not find project": Check your project IDs are correct in variables.tf
- Other errors: Read the error message carefully. It usually tells you what is wrong.

### Deploy the Infrastructure

If the plan looks correct, deploy it:

```bash
tofu apply
```

OpenTofu will show the plan again and ask for confirmation:

```
Do you want to perform these actions?
  OpenTofu will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:
```

Type `yes` and press Enter.

OpenTofu will now create all the resources. This takes 5-10 minutes. You will see progress messages as each resource is created.

**When it completes, you will see:**

```
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:

blue_linux_floating_ips = [
  "100.65.4.31",
]
...
```

The outputs show the IP addresses of your servers. You will use these to connect.

### Verify in OpenStack Dashboard

1. Open https://openstack.cyberrange.rit.edu
2. Switch between your three projects (dropdown in top left)
3. Go to Compute, then Instances
4. You should see:
   - Main project: Scoring server(s)
   - Blue project: Windows and Linux servers
   - Red project: Kali servers

Return to your project root directory:

```bash
cd ..
```

---

## Generate Ansible Inventory

Ansible needs to know which servers exist and how to connect to them. A Python script generates this information from OpenTofu.

### Run the Import Script

```bash
python3 import-tofu-to-ansible.py
```

You should see output like:

```
Reading OpenTofu outputs...
Generating inventory file...
Wrote inventory to ansible/inventory/production.ini
```

### Verify the Inventory

Look at the generated file:

```bash
cat ansible/inventory/production.ini
```

You should see groups of servers with their IP addresses:

```ini
[scoring]
scoring-1 ansible_host=10.10.10.11 floating_ip=100.65.4.11

[windows_dc]
dc01 ansible_host=10.10.10.21 floating_ip=100.65.4.21

[blue_windows_members]
blue-win-2 ansible_host=10.10.10.22 floating_ip=100.65.4.22

[blue_linux_members]
webserver ansible_host=10.10.10.31 floating_ip=100.65.4.31

[red_team]
red-kali-1 ansible_host=10.10.10.41 floating_ip=100.65.4.41
red-kali-2 ansible_host=10.10.10.42 floating_ip=100.65.4.42
...
```

---

## Configure Servers with Ansible

Ansible will now configure all the servers: set up the domain controller, join servers to the domain, create user accounts, and enable remote desktop.

### Prepare the Ansible Control Node

Due to network restrictions, running Ansible from your local computer can be unreliable. Instead, you will run Ansible from one of the Linux servers inside the cloud.

**Find a Linux server's floating IP:**

Look at the inventory file or OpenTofu outputs. Choose one of the Blue Linux servers.

**Copy the ansible directory to that server:**

```bash
scp -r -J sshjump@ssh.cyberrange.rit.edu ansible/ cyberrange@<floating-ip>:~/
```

Replace `<floating-ip>` with the actual IP address (like `100.65.4.31`).

When prompted for a password, enter: `Cyberrange123!`

**Connect to the server:**

```bash
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<floating-ip>
```

Password: `Cyberrange123!`

### Install Ansible on the Control Node

Once connected to the Linux server:

```bash
sudo apt update
sudo apt install -y ansible
```

Verify installation:

```bash
ansible --version
```

### Run the Playbooks

Navigate to the ansible directory and run the main playbook:

```bash
cd ~/ansible
ansible-playbook playbooks/site.yml
```

**What to expect:**

This process takes 30-60 minutes. Ansible will:

1. Validate the inventory
2. Set up the Windows Domain Controller
3. Join Windows member servers to the domain
4. Activate Windows licenses
5. Join Linux servers to the domain
6. Create domain user accounts
7. Set up remote desktop on all servers

You will see lots of output as each task runs. Green text means success. Yellow text means something changed. Red text means an error.

**If you see errors:**

- "unreachable" errors early on: Windows servers take 15-20 minutes to boot. Wait and try again.
- "authentication failed": Check that the inventory has correct passwords
- Other errors: Read the error message. It usually explains what went wrong.

You can re-run the playbook safely. Ansible will skip tasks that are already complete.

### Exit the Control Node

When Ansible completes successfully, exit back to your local computer:

```bash
exit
```

---

## Verify Everything Works

Test that all servers are accessible and configured correctly.

### Test SSH to Linux Servers

From your local computer:

```bash
# Connect to a Blue Linux server
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<blue-linux-floating-ip>
# Password: Cyberrange123!

# Try a domain user
ssh -J sshjump@ssh.cyberrange.rit.edu jdoe@<blue-linux-floating-ip>
# Password: UserPass123!
```

### Test SSH to Red Team Kali

```bash
ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<kali-floating-ip>
# Password: Cyberrange123!
```

Kali boxes do not join the domain, so only the cyberrange local account works.

### Test RDP to Windows Servers

Windows servers use Remote Desktop Protocol (RDP). You need to create an SSH tunnel:

**Terminal 1 - Create the tunnel:**

```bash
ssh -L 3389:<windows-floating-ip>:3389 sshjump@ssh.cyberrange.rit.edu -N
```

Keep this running (it will not show any output).

**Connect with RDP client:**

- On Windows: Open "Remote Desktop Connection," connect to `localhost`
- On macOS: Download "Microsoft Remote Desktop" from App Store, connect to `localhost`
- On Linux: Install `freerdp2-x11`, run `xfreerdp /v:localhost`

**Credentials:**
- Domain Administrator: `CDT\Administrator` / `Cyberrange123!`
- Domain user: `CDT\jdoe` / `UserPass123!`

### Test RDP to Linux Servers (xRDP)

Linux servers have xRDP installed for graphical access. Use the same tunnel method as Windows:

```bash
ssh -L 3389:<linux-floating-ip>:3389 sshjump@ssh.cyberrange.rit.edu -N
```

Connect with your RDP client to `localhost`. At the xRDP login screen:
- Session: Xorg
- Username: `jdoe` (or other domain user)
- Password: `UserPass123!`

### Troubleshooting Connection Issues

**Cannot connect to jump host:**
- Check your internet connection
- Try the web SSH client at https://ssh.cyberrange.rit.edu

**Connection to server times out:**
- Verify the IP address is correct
- Check if the server is running in OpenStack dashboard
- Windows servers take 15-20 minutes to fully boot

**Authentication fails:**
- Double-check the password
- For domain users, make sure the domain setup completed
- Try the local cyberrange account

**RDP shows black screen:**
- Wait 30 seconds for the desktop to load
- Try disconnecting and reconnecting
- For Linux xRDP, make sure you selected "Xorg" session type

---

## What is Next

You have successfully deployed the base infrastructure. From here:

**Customize for your competition:**
- See the README.md section "Customizing for Your Competition"
- Add more servers, services, and network segments as needed

**Plan your competition:**
- Work through the STUDENT-CHECKLIST.md
- Design your network topology, scored services, and scenarios

**Learn more about the tools:**
- README.md explains OpenTofu and Ansible concepts
- ansible/README.md explains how to create new playbooks and roles

**Connect to your servers:**
- See CONNECTIVITY-GUIDE.md for all connection methods

---

## Quick Reference

| Task | Command |
|------|---------|
| Load credentials | `source app-cred-openrc.sh` |
| Preview changes | `cd opentofu && tofu plan` |
| Deploy infrastructure | `cd opentofu && tofu apply` |
| Destroy infrastructure | `cd opentofu && tofu destroy` |
| Regenerate inventory | `python3 import-tofu-to-ansible.py` |
| Run all Ansible playbooks | `ansible-playbook playbooks/site.yml` |
| SSH to Linux server | `ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<ip>` |
| RDP tunnel | `ssh -L 3389:<ip>:3389 sshjump@ssh.cyberrange.rit.edu -N` |

| Account | Username | Password |
|---------|----------|----------|
| Linux/Windows local | cyberrange | Cyberrange123! |
| Domain Administrator | Administrator | Cyberrange123! |
| Domain users | jdoe, asmith, etc. | UserPass123! |
