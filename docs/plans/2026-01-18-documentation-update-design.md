# Documentation Update Design

## Overview

Update all documentation to reflect the new multi-project architecture (Grey/Blue/Red teams with RBAC network sharing) and create a new step-by-step deployment guide for complete beginners.

## Target Audience

- Students new to Ansible, Terraform/OpenTofu, and command-line tools
- Assume no prior terminal or DevOps experience
- Building CCDC-style attack/defend CTF competitions
- 6 teams, each acting as Grey Team for their own competition

## Student Context

- Instructor pre-provisions three OpenStack projects per team (main, blue, red)
- Students receive project NAMES and look up IDs in OpenStack dashboard
- Single application credential from main project works for all three projects
- Each Grey Team deploys infrastructure for one Blue Team and one Red Team

## Terminology

Keep existing conventions:
- Grey Team, Blue Team, Red Team
- CDT.local domain
- cyberrange user account
- Existing password conventions

---

## Files to Update

### 1. DEPLOYMENT-GUIDE.md (New File)

Step-by-step beginner guide. Assume zero prior knowledge.

**Structure:**

1. Before You Begin
   - What you will need (computer, internet, approximately 2 hours)
   - What you will receive from instructor (three project names)
   - What you will build (diagram of end result)

2. Understanding the Basics
   - What is a terminal and how to open one (macOS, Windows, Linux)
   - What is a command and running your first command
   - What are these tools (1-2 sentence explanations of Git, OpenTofu, Ansible)

3. Install Required Software
   - Git with verification steps
   - OpenTofu with verification steps
   - Ansible with verification steps
   - Python 3 with verification steps
   - Troubleshooting common installation issues

4. Set Up SSH Keys
   - What is an SSH key and why you need one
   - Check if you have one
   - Create one if needed
   - Upload to OpenStack with detailed steps

5. Get Your OpenStack Project IDs
   - Log into OpenStack dashboard
   - Navigate to Identity then Projects
   - Find your three projects and copy their IDs
   - Where to record them

6. Create Application Credentials
   - What are application credentials
   - Create one in your main project
   - Download the openrc file
   - Move it to your project directory

7. Clone and Configure the Repository
   - Clone the repo
   - Run quick-start.sh
   - Edit variables.tf with your project IDs and SSH key name

8. Deploy Infrastructure
   - Source credentials
   - Run tofu plan with explanation of output
   - Run tofu apply
   - Wait and verify in OpenStack dashboard

9. Generate Ansible Inventory
   - Run the import script
   - Verify the inventory file

10. Configure Servers with Ansible
    - Copy files to control node
    - SSH to control node
    - Install Ansible
    - Run playbooks
    - What to expect (timing, output)

11. Verify Everything Works
    - Check each server type
    - Test connectivity
    - Common issues and fixes

12. What is Next
    - Links to customization sections in README
    - Links to STUDENT-CHECKLIST for competition prep

---

### 2. README.md (Major Rewrite)

**New Structure:**

1. Introduction
   - Template for Grey Teams building CCDC-style competitions
   - Creates infrastructure across three OpenStack projects
   - Brief explanation of Grey/Blue/Red team roles

2. Architecture Overview
   - ASCII diagram showing three projects and network sharing
   - IP address scheme table:
     - Scoring: 10.10.10.1x (Grey Team, main project)
     - Blue Windows: 10.10.10.2x (Blue Team, blue project)
     - Blue Linux: 10.10.10.3x (Blue Team, blue project)
     - Red Kali: 10.10.10.4x (Red Team, red project)
   - Explanation of RBAC network sharing

3. What Gets Created
   - Main project: Network, router, scoring server(s)
   - Blue project: Windows DC, Windows members, Linux servers
   - Red project: Kali attack boxes
   - Note that this is a starting point, not complete competition

4. Prerequisites
   - Brief list with links to DEPLOYMENT-GUIDE.md for details

5. Quick Start
   - Condensed steps for experienced users

6. Understanding the Tools
   - Keep existing OpenTofu explanation
   - Keep existing Ansible explanation
   - Keep existing "How They Work Together" section

7. Customizing for Your Competition
   - Update examples for multi-project structure
   - Show provider aliases in examples
   - Update inventory group references

8. OpenTofu Basics
   - Keep existing content
   - Add section on provider aliases

9. Ansible Basics
   - Keep existing content
   - Update inventory examples with new groups

10. Common Operations
    - Update for multi-project workflow

11. Troubleshooting
    - Keep existing content
    - Add multi-project specific issues (wrong project ID, RBAC errors)

---

### 3. ansible/README.md (Moderate Updates)

**Sections to Update:**

1. "What This Configuration Does"
   - Update to reflect team structure
   - Note that playbooks target teams, not individual machines
   - Explain Red Team Kali boxes only get xRDP (no domain join)

2. "Directory Structure"
   - Update inventory description with new groups
   - Explain group hierarchy

3. "Understanding the Existing Configuration"
   - Update site.yml description
   - Explain which playbooks run on which teams

**New Section to Add:**

"Inventory Groups Explained"
- Table showing each group and contents:
  - scoring: Grey Team scoring servers
  - windows_dc: First Blue Windows VM (Domain Controller)
  - blue_windows_members: Blue Windows VMs except DC
  - blue_linux_members: Blue Linux VMs
  - red_team: Red Team Kali VMs
  - windows (hierarchy): windows_dc + blue_windows_members
  - blue_team (hierarchy): all Blue VMs
  - linux_members (hierarchy): blue_linux + red_team + scoring
- How to target specific teams in playbooks

**Keep As-Is:**
- "How Ansible Works"
- "Running Playbooks"
- "Creating Roles"
- "Working with Variables"
- "Debugging Problems"
- "Useful Ansible Modules"

---

### 4. CONNECTIVITY-GUIDE.md (Minor Updates)

**Sections to Update:**

1. "Network Overview"
   - Update IP ranges table with team context
   - Add team ownership to each range

2. "Default Credentials"
   - Add Kali credentials (same as other Linux)
   - Note that Red Team Kali boxes do not join domain

3. "Connecting to Different Server Types"
   - Add Kali section (SSH and xRDP access)
   - Note pre-installed security tools

4. "Quick Reference" table
   - Add row for Kali boxes

**Keep As-Is:**
- All connection methods
- All troubleshooting sections
- Ansible connectivity section
- File copying instructions

---

### 5. STUDENT-CHECKLIST.md (Moderate Updates)

**Phase 1: Environment Setup**
- Add: Record your three project names from instructor
- Add: Look up project IDs in OpenStack dashboard
- Update variables.tf step to include project IDs
- Update verification to show resources in three projects

**Phase 2: Design Your Competition**
- Keep mostly as-is
- Add note that template provides base infrastructure to extend

**Phase 3: Build Infrastructure with OpenTofu**
- Reference new file structure
- Note security groups are per-project
- Update examples to show provider aliases
- Add guidance on targeting specific projects

**Phase 4: Update Inventory Script**
- Explain new output structure organized by team
- Show new inventory groups
- Explain adding custom groups

**Phase 5: Build Ansible Configuration**
- Reference new inventory groups
- Note playbooks apply to specific teams

**Phases 6-9**
- Minimal changes (competition-specific, not architecture-specific)

---

### 6. CLAUDE.md (Review)

Verify consistency with final documentation state. The file was recently updated for multi-project architecture, so changes should be minimal.

---

## Writing Order

1. DEPLOYMENT-GUIDE.md (foundational, referenced by others)
2. README.md (main entry point, references deployment guide)
3. ansible/README.md (standalone)
4. CONNECTIVITY-GUIDE.md (quick updates)
5. STUDENT-CHECKLIST.md (references other docs)
6. CLAUDE.md review

## Constraints

- No emojis in any documentation
- Keep existing code examples where still accurate
- Use consistent terminology throughout
- Assume reader has zero command-line experience for DEPLOYMENT-GUIDE
- Assume reader is learning for README and other docs
