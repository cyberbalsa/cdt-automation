# Grey Team Competition Build Checklist

This checklist guides you through building your competition infrastructure. Work through each section in order. Do not skip steps.

---

## Phase 1: Environment Setup

Complete these steps before writing any code.

### 1.1 Install Required Software

Run each command to verify the tool is installed. If a command fails, install the tool before continuing.

```bash
# Check Git
git --version

# Check OpenTofu
tofu version

# Check Ansible
ansible --version

# Check Python
python3 --version
```

- [ ] Git installed and working
- [ ] OpenTofu installed and working
- [ ] Ansible installed and working
- [ ] Python 3 installed and working

### 1.2 Create SSH Key

Windows servers require RSA keys. Check if you have one:

```bash
ls ~/.ssh/id_rsa*
```

If no files appear, create a key:

```bash
ssh-keygen -t rsa -b 4096
```

- [ ] RSA SSH key pair exists at ~/.ssh/id_rsa and ~/.ssh/id_rsa.pub

### 1.3 Configure OpenStack Access

1. Go to https://openstack.cyberrange.rit.edu
2. Log in with your credentials
3. Navigate to Compute, then Key Pairs
4. Click Import Public Key
5. Enter a name for your key (write it down)
6. Run `cat ~/.ssh/id_rsa.pub` and paste the output
7. Click Import Public Key

- [ ] SSH public key uploaded to OpenStack
- [ ] Key name recorded: ________________

### 1.4 Create Application Credentials

1. In OpenStack, navigate to Identity, then Application Credentials
2. Click Create Application Credential
3. Enter a name (like "grey-team")
4. Click Create Application Credential
5. Click Download openrc file
6. Save the file - the secret is only shown once

- [ ] Application credentials created
- [ ] openrc file downloaded

### 1.5 Set Up This Project

```bash
# Clone the repository (if not already done)
git clone <your-repo-url>
cd cdt-automation

# Move your credentials file here
mv ~/Downloads/app-cred-*-openrc.sh .

# Run setup script
./quick-start.sh
```

- [ ] Project cloned
- [ ] Credentials file in project directory
- [ ] quick-start.sh ran successfully

### 1.6 Configure Your SSH Key Name

Edit `opentofu/variables.tf` and find the keypair_name variable. Change it to match the name you used in OpenStack.

- [ ] keypair_name variable updated in variables.tf

### 1.7 Verify Setup

```bash
# Load credentials
source app-cred-openrc.sh

# Initialize OpenTofu
cd opentofu
tofu init

# Verify OpenTofu can connect to OpenStack
tofu plan
```

If `tofu plan` shows resources it would create without errors, your setup is complete.

- [ ] `source app-cred-openrc.sh` runs without errors
- [ ] `tofu init` completes successfully
- [ ] `tofu plan` shows planned resources without authentication errors

---

## Phase 2: Design Your Competition

Complete your design on paper before writing code. Changing your design after building infrastructure wastes time.

### 2.1 Network Design

Draw your network topology. Your competition must have:

- [ ] Remote/DMZ network segment (publicly accessible services)
- [ ] Local/Internal network segment (internal services)
- [ ] Router or firewall between segments
- [ ] Management network (for Grey Team monitoring)
- [ ] Red Team network (isolated attack infrastructure)

Write down your IP addressing scheme:

| Network | CIDR | Purpose |
|---------|------|---------|
| DMZ | ___.___.___.___/___ | ________________ |
| Internal | ___.___.___.___/___ | ________________ |
| Management | ___.___.___.___/___ | ________________ |
| Red Team | ___.___.___.___/___ | ________________ |

- [ ] Network topology drawn
- [ ] IP addressing scheme documented

### 2.2 System Inventory

List every system your competition needs. Remember:

- Every Blue Team member needs a dedicated workstation
- Every Red Team member needs a dedicated workstation
- You need at least 2 Windows systems
- You need at least 3 Linux systems
- You need at least 5 scored services

Fill in your system inventory:

| Hostname | IP Address | OS | Purpose | Scored? |
|----------|------------|----|---------|---------|
| | | | | |
| | | | | |
| | | | | |
| | | | | |
| | | | | |

(Add more rows as needed)

- [ ] All servers listed with hostnames and IPs
- [ ] At least 2 Windows systems included
- [ ] At least 3 Linux systems included
- [ ] Blue Team workstations included (one per member)
- [ ] Red Team workstations included (one per member)
- [ ] Scored services identified

### 2.3 Scored Services

List every service that will be scored:

| Service Name | Host | Port | Check Method | Points |
|--------------|------|------|--------------|--------|
| | | | | |
| | | | | |
| | | | | |
| | | | | |
| | | | | |

- [ ] At least 5 scored services defined
- [ ] Check method documented for each service
- [ ] Point values assigned

### 2.4 Credentials

Plan your credentials. Document them now so you do not forget:

| System/Service | Username | Password | Purpose |
|----------------|----------|----------|---------|
| | | | |
| | | | |
| | | | |

- [ ] All credentials documented
- [ ] Credentials stored securely

---

## Phase 3: Build Infrastructure with OpenTofu

Now translate your design into OpenTofu configuration.

### 3.1 Create Network Resources

Edit `opentofu/network.tf` to add your network segments.

For each network in your design:

```hcl
resource "openstack_networking_network_v2" "NETWORK_NAME" {
  name           = "competition-NETWORK_NAME"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "NETWORK_NAME_subnet" {
  name            = "competition-NETWORK_NAME-subnet"
  network_id      = openstack_networking_network_v2.NETWORK_NAME.id
  cidr            = "YOUR.CIDR.HERE/24"
  ip_version      = 4
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}
```

- [ ] DMZ network resource created
- [ ] Internal network resource created
- [ ] Management network resource created
- [ ] Red Team network resource created
- [ ] Router/firewall resource created (if using pfSense or similar)

### 3.2 Create Instance Resources

Edit `opentofu/instances.tf` to add your servers.

For each server type, add a resource block. Use the existing Windows and Debian resources as templates.

- [ ] Scored service servers added (web, mail, database, etc.)
- [ ] Blue Team workstations added
- [ ] Red Team workstations added
- [ ] Management/scoring server added

### 3.3 Create Variables

Edit `opentofu/variables.tf` to add variables for configurable values:

- [ ] Server count variables added
- [ ] Network CIDR variables added
- [ ] Image name variables added
- [ ] Any team-size variables added

### 3.4 Create Outputs

Edit `opentofu/outputs.tf` to output IP addresses for all your servers:

- [ ] Outputs added for all server types
- [ ] Outputs include both internal and floating IPs

### 3.5 Test OpenTofu Configuration

```bash
source app-cred-openrc.sh
cd opentofu
tofu plan
```

Review the plan output carefully. Verify:

- [ ] All expected networks will be created
- [ ] All expected servers will be created
- [ ] IP addresses match your design
- [ ] No errors in the plan output

### 3.6 Deploy Infrastructure

When the plan looks correct:

```bash
tofu apply
```

Type `yes` to confirm.

- [ ] `tofu apply` completed successfully
- [ ] All resources created in OpenStack dashboard

### 3.7 Record Outputs

```bash
tofu output
```

Copy and save this information. You will need it for Ansible and documentation.

- [ ] All IP addresses recorded

---

## Phase 4: Update Inventory Script

The `import-tofu-to-ansible.py` script must be updated to include your new server types.

### 4.1 Understand the Script

Read through `import-tofu-to-ansible.py` to understand how it works:

1. It runs `tofu output -json` to get server information
2. It parses the JSON to extract hostnames and IPs
3. It writes an Ansible inventory file with groups and variables

- [ ] Script logic understood

### 4.2 Add Your Server Types

Edit the script to include inventory groups for your new server types. Follow the patterns used for existing groups.

For each new server type:
1. Add code to extract IPs from the tofu output
2. Add a new inventory group section
3. Add appropriate connection variables

- [ ] DMZ servers added to inventory script
- [ ] Blue Team workstations added to inventory script
- [ ] Red Team workstations added to inventory script
- [ ] Any other server types added

### 4.3 Test Inventory Generation

```bash
python3 import-tofu-to-ansible.py
cat ansible/inventory/production.ini
```

Verify the inventory file contains:
- [ ] All servers with correct IPs
- [ ] Servers in correct groups
- [ ] Connection variables for each group

---

## Phase 5: Build Ansible Configuration

Now create Ansible playbooks and roles to configure your servers.

### 5.1 Create Role Directory Structure

For each service type, create a role:

```bash
# Example for a web server role
mkdir -p ansible/roles/webserver/{tasks,handlers,templates,defaults,files}
```

- [ ] Role directories created for each service type

### 5.2 Write Role Tasks

For each role, create `tasks/main.yml` with the configuration tasks.

Use the existing roles (domain_controller, linux_domain_member, domain_users) as examples.

- [ ] Tasks written for each role
- [ ] Tasks tested individually

### 5.3 Create Playbooks

For each role, create a playbook in `ansible/playbooks/`:

```yaml
---
- name: Configure Service Name
  hosts: your_server_group
  become: true
  roles:
    - your_role_name
```

- [ ] Playbook created for each service
- [ ] Playbooks use correct host groups

### 5.4 Update site.yml

Edit `ansible/playbooks/site.yml` to import your new playbooks:

```yaml
- name: Configure Your Service
  import_playbook: your-playbook.yml
```

Order matters. Put playbooks in the order they should run (dependencies first).

- [ ] All playbooks imported in site.yml
- [ ] Playbooks ordered correctly (dependencies first)

### 5.5 Add Variables

Edit `ansible/group_vars/` files to add variables for your services.

Create new group_vars files for new groups if needed.

- [ ] Variables defined for all services
- [ ] Credentials stored in variables (not hardcoded in tasks)

### 5.6 Test Ansible Playbooks

Run playbooks one at a time to test them:

```bash
cd ansible
ansible-playbook playbooks/your-first-playbook.yml -v
```

Fix any errors before running the next playbook.

- [ ] Each playbook tested individually
- [ ] All playbooks run successfully

### 5.7 Test Full Deployment

Run the complete site.yml:

```bash
ansible-playbook playbooks/site.yml
```

- [ ] Full site.yml runs without errors
- [ ] All services configured correctly

---

## Phase 6: Build Scoring Engine

Your competition needs automated service checks.

### 6.1 Choose Scoring Approach

Decide how you will implement scoring:

- [ ] Option A: Custom Python scoring engine
- [ ] Option B: Existing tool (ScoreStack, etc.)
- [ ] Option C: Ansible-based checks with logging
- [ ] Option D: Other (specify): ________________

### 6.2 Implement Service Checks

For each scored service, implement a check that:
1. Tests if the service is responding
2. Verifies the service returns expected content
3. Logs the result with timestamp

- [ ] Check implemented for service 1: ________________
- [ ] Check implemented for service 2: ________________
- [ ] Check implemented for service 3: ________________
- [ ] Check implemented for service 4: ________________
- [ ] Check implemented for service 5: ________________

### 6.3 Implement Scoring Logic

- [ ] Points calculation implemented
- [ ] Score storage implemented (database or files)
- [ ] Score display implemented (dashboard or logs)

### 6.4 Automate Check Execution

- [ ] Checks run automatically on schedule
- [ ] Schedule interval matches requirements (every 1-5 minutes)

### 6.5 Test Scoring Engine

- [ ] Scoring engine starts successfully
- [ ] Checks execute on schedule
- [ ] Scores recorded correctly
- [ ] Scores display correctly

---

## Phase 7: Full Deployment Test

Before competition week, do a complete deployment from scratch.

### 7.1 Destroy Existing Infrastructure

```bash
cd opentofu
source ../app-cred-openrc.sh
tofu destroy
```

- [ ] All infrastructure destroyed

### 7.2 Deploy Fresh

```bash
tofu apply
cd ..
python3 import-tofu-to-ansible.py
```

- [ ] Infrastructure deployed successfully
- [ ] Inventory generated

### 7.3 Configure Everything

SSH to your Ansible control node and run the full playbook:

```bash
cd ansible
ansible-playbook playbooks/site.yml
```

Time how long this takes.

- [ ] Full configuration completed
- [ ] Deployment time recorded: _______ minutes

### 7.4 Start Scoring Engine

- [ ] Scoring engine deployed and running
- [ ] All checks passing for working services

### 7.5 Test Team Access

Verify that team members can access their workstations:

- [ ] Blue Team workstation 1 accessible
- [ ] Blue Team workstation 2 accessible
- [ ] (continue for all Blue Team workstations)
- [ ] Red Team workstation 1 accessible
- [ ] Red Team workstation 2 accessible
- [ ] (continue for all Red Team workstations)

### 7.6 Test Service Access

Verify all scored services are accessible and working:

- [ ] Service 1 working and scoring
- [ ] Service 2 working and scoring
- [ ] Service 3 working and scoring
- [ ] Service 4 working and scoring
- [ ] Service 5 working and scoring

### 7.7 Document Issues

Record any problems encountered during deployment:

| Issue | Cause | Solution |
|-------|-------|----------|
| | | |
| | | |
| | | |

- [ ] All issues documented
- [ ] All issues resolved or have workarounds

---

## Phase 8: Documentation

Complete all required documentation.

### 8.1 Grey Team Design Document

Your main document (30-50 pages) covering:

- [ ] Executive summary
- [ ] Competition scenario
- [ ] Network architecture with diagrams
- [ ] System specifications
- [ ] Scored services
- [ ] Competition rules
- [ ] Assessment and scoring
- [ ] Team packets overview
- [ ] Deployment plan
- [ ] Operations plan
- [ ] Educational justification
- [ ] Risk assessment

### 8.2 Red Team Packet

Document for Red Team (10-15 pages):

- [ ] Scenario from Red Team perspective
- [ ] Objectives and success criteria
- [ ] Network topology (appropriate detail level)
- [ ] Rules of engagement
- [ ] Tool allowances/restrictions
- [ ] Reporting requirements
- [ ] Red Team template

### 8.3 Blue Team Packet

Document for Blue Team (15-20 pages):

- [ ] Scenario from Blue Team perspective
- [ ] Mission and success criteria
- [ ] Complete network topology
- [ ] System inventory with credentials
- [ ] Service requirements
- [ ] Rules and constraints
- [ ] Blue Team template

### 8.4 Network Diagrams

- [ ] Professional quality diagram created
- [ ] Editable source file saved
- [ ] PDF version exported
- [ ] Version for Red Team packet (may hide details)
- [ ] Version for Blue Team packet (full details)

### 8.5 Grey Team Operations Manual

Internal document (10-15 pages):

- [ ] Pre-competition checklist
- [ ] Deployment checklist
- [ ] Day 0 runbook
- [ ] Competition day procedures
- [ ] Common issues and solutions
- [ ] Scoring verification procedures
- [ ] Emergency procedures

### 8.6 Code Documentation

- [ ] README files for all custom code
- [ ] Comments in complex code sections
- [ ] Setup instructions for scoring engine

---

## Phase 9: Pre-Competition Final Checks

One week before competition.

### 9.1 Instructor Approval

- [ ] Design document submitted to instructor
- [ ] Feedback received and addressed
- [ ] Final approval obtained

### 9.2 Final Deployment Test

- [ ] Complete fresh deployment successful
- [ ] Deployment time acceptable
- [ ] All services working
- [ ] Scoring engine working
- [ ] Team access verified

### 9.3 Team Coordination

- [ ] Grey Team roles assigned for competition week
- [ ] Communication channels established
- [ ] Emergency contact information shared

### 9.4 Contingency Plans

- [ ] Backup plan for infrastructure failure
- [ ] Backup plan for scoring engine failure
- [ ] Backup plan for network issues

---

## Competition Week

### Day 0 (Prep Day)

- [ ] Infrastructure deployed and ready
- [ ] Scoring engine running
- [ ] Presentation materials ready
- [ ] Red Team packet ready to distribute
- [ ] Blue Team packet ready to distribute
- [ ] Red Team access verified
- [ ] Blue Team access verified
- [ ] Introduction completed
- [ ] Rules reviewed with all teams
- [ ] Questions answered

### Days 1-3 (Competition)

- [ ] Competition started on time
- [ ] Scoring running throughout
- [ ] Issues tracked and resolved
- [ ] Grey Team monitoring continuously
- [ ] Team communications handled
- [ ] End-of-day status announced

### Day 4 (Purple Day)

- [ ] Red Team presentation completed
- [ ] Blue Team presentation completed
- [ ] Grey Team behind-the-scenes shared

### Day 5 (Lessons Learned)

- [ ] All team members spoke
- [ ] Lessons documented
- [ ] Competition infrastructure cleaned up

---

## Post-Competition

- [ ] Final scores calculated
- [ ] Results announced
- [ ] Infrastructure destroyed
- [ ] Documentation archived
- [ ] Lessons learned documented for future teams
