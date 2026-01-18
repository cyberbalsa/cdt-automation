# Multi-Project Grey Team Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor OpenTofu configuration to deploy infrastructure across three OpenStack projects (main/scoring, blue team, red team) with RBAC network sharing.

**Architecture:** Three provider aliases target different OpenStack projects using `tenant_id`. Network and router live in main project, shared to blue/red via RBAC policies. VMs deployed to their respective projects connect to the shared network.

**Tech Stack:** OpenTofu/Terraform, OpenStack provider, Python (inventory generator), Ansible

**Design Document:** `docs/plans/2026-01-17-multi-project-greyteam-design.md`

---

## Task 1: Add Project ID Variables

**Files:**
- Modify: `opentofu/variables.tf`

**Step 1: Add project ID variables to variables.tf**

Add after the existing variables (around line 260):

```hcl
# ------------------------------------------------------------------------------
# PROJECT CONFIGURATION (Multi-Project Grey Team)
# ------------------------------------------------------------------------------
# These variables specify which OpenStack projects to deploy resources to.
# Requires credentials with access to all three projects.

variable "main_project_id" {
  description = "OpenStack project ID for main/scoring infrastructure (e.g., cdtalpha)"
  type        = string
  default     = "04846fb2e027424d8898953062787b16"
}

variable "blue_project_id" {
  description = "OpenStack project ID for Blue Team (e.g., cdtalpha-cdtbravo)"
  type        = string
  default     = "d25474b0db314855b36e659c777893c1"
}

variable "red_project_id" {
  description = "OpenStack project ID for Red Team (e.g., cdtalpha-cdtcharlie)"
  type        = string
  default     = "4cba761707eb4606a750fb7b3de3948d"
}
```

**Step 2: Validate syntax**

Run: `cd /root/cdt-automation/opentofu && tofu validate`
Expected: Success (may warn about unused variables, that's OK)

**Step 3: Commit**

```bash
git add opentofu/variables.tf
git commit -m "feat(tofu): add project ID variables for multi-project deployment"
```

---

## Task 2: Add VM Count and Image Variables

**Files:**
- Modify: `opentofu/variables.tf`

**Step 1: Replace existing VM count variables**

Find and replace the `windows_count` variable (around line 163-177) with:

```hcl
variable "scoring_count" {
  description = "Number of scoring servers to create in main project"
  type        = number
  default     = 1
}

variable "blue_windows_count" {
  description = "Number of Blue Team Windows VMs (first becomes Domain Controller)"
  type        = number
  default     = 2
}
```

Find and replace the `debian_count` variable (around line 179-192) with:

```hcl
variable "blue_linux_count" {
  description = "Number of Blue Team Linux VMs"
  type        = number
  default     = 2
}

variable "red_kali_count" {
  description = "Number of Red Team Kali attack VMs"
  type        = number
  default     = 2
}
```

**Step 2: Add new image variables**

Add after `debian_image_name` variable (around line 110):

```hcl
variable "scoring_image_name" {
  description = "Name of the image for scoring servers"
  type        = string
  default     = "Ubuntu2404Desktop"
}

variable "kali_image_name" {
  description = "Name of the Kali Linux image for Red Team"
  type        = string
  default     = "kali-2024"
}
```

**Step 3: Replace hostname variables**

Find and replace `windows_hostnames` (around line 199-221) with:

```hcl
variable "blue_windows_hostnames" {
  description = "Custom hostnames for Blue Team Windows VMs (optional)"
  type        = list(string)
  default     = ["dc01"]
}
```

Find and replace `debian_hostnames` (around line 223-236) with:

```hcl
variable "blue_linux_hostnames" {
  description = "Custom hostnames for Blue Team Linux VMs (optional)"
  type        = list(string)
  default     = ["webserver"]
}
```

**Step 4: Validate syntax**

Run: `cd /root/cdt-automation/opentofu && tofu validate`
Expected: Errors about references to old variable names (expected, we'll fix in later tasks)

**Step 5: Commit**

```bash
git add opentofu/variables.tf
git commit -m "feat(tofu): add team-specific VM count, image, and hostname variables"
```

---

## Task 3: Configure Provider Aliases

**Files:**
- Modify: `opentofu/main.tf`

**Step 1: Update the existing provider block to be the main provider with alias**

Replace the existing `provider "openstack"` block (around line 29-35) with:

```hcl
# Default provider (main project) - used when no provider is specified
provider "openstack" {
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.main_project_id
}

# Aliased provider for main project (explicit usage)
provider "openstack" {
  alias     = "main"
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.main_project_id
}

# Blue Team project provider
provider "openstack" {
  alias     = "blue"
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.blue_project_id
}

# Red Team project provider
provider "openstack" {
  alias     = "red"
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.red_project_id
}
```

**Step 2: Validate syntax**

Run: `cd /root/cdt-automation/opentofu && tofu validate`
Expected: Errors about variable references (expected)

**Step 3: Commit**

```bash
git add opentofu/main.tf
git commit -m "feat(tofu): add provider aliases for main, blue, and red projects"
```

---

## Task 4: Add RBAC Network Sharing Policies

**Files:**
- Modify: `opentofu/network.tf`

**Step 1: Add provider to existing network resources**

Add `provider = openstack.main` to the `cdt_net` resource (around line 32):

```hcl
resource "openstack_networking_network_v2" "cdt_net" {
  provider = openstack.main
  name     = var.network_name
}
```

Add `provider = openstack.main` to the `cdt_subnet` resource (around line 56):

```hcl
resource "openstack_networking_subnet_v2" "cdt_subnet" {
  provider   = openstack.main
  name       = "${var.network_name}-subnet"
  # ... rest unchanged
}
```

Add `provider = openstack.main` to the `cdt_router` resource (around line 98):

```hcl
resource "openstack_networking_router_v2" "cdt_router" {
  provider            = openstack.main
  name                = var.router_name
  external_network_id = data.openstack_networking_network_v2.ext_net.id
}
```

Add `provider = openstack.main` to the `cdt_router_interface` resource (around line 120):

```hcl
resource "openstack_networking_router_interface_v2" "cdt_router_interface" {
  provider  = openstack.main
  router_id = openstack_networking_router_v2.cdt_router.id
  subnet_id = openstack_networking_subnet_v2.cdt_subnet.id
}
```

**Step 2: Add RBAC policies at the end of network.tf**

Add before the final comment block:

```hcl
# ==============================================================================
# RBAC POLICIES - SHARE NETWORK WITH SUBPROJECTS
# ==============================================================================
# These policies allow Blue and Red team projects to use the network
# created in the main project. VMs in those projects can attach to this network.
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_rbac_policy_v2

resource "openstack_networking_rbac_policy_v2" "share_with_blue" {
  provider      = openstack.main
  action        = "access_as_shared"
  object_id     = openstack_networking_network_v2.cdt_net.id
  object_type   = "network"
  target_tenant = var.blue_project_id
}

resource "openstack_networking_rbac_policy_v2" "share_with_red" {
  provider      = openstack.main
  action        = "access_as_shared"
  object_id     = openstack_networking_network_v2.cdt_net.id
  object_type   = "network"
  target_tenant = var.red_project_id
}
```

**Step 3: Validate syntax**

Run: `cd /root/cdt-automation/opentofu && tofu validate`
Expected: Errors about instance references (expected, we'll fix next)

**Step 4: Commit**

```bash
git add opentofu/network.tf
git commit -m "feat(tofu): add RBAC policies to share network with blue and red projects"
```

---

## Task 5: Refactor Security Groups Per Project

**Files:**
- Modify: `opentofu/security.tf`

**Step 1: Read current security.tf**

Run: `cat /root/cdt-automation/opentofu/security.tf`
Understand the existing security group structure.

**Step 2: Add provider to existing security groups and rename for blue team**

For the Windows security group, change:
- Resource name from `windows_sg` to `blue_windows_sg`
- Add `provider = openstack.blue`

For the Linux security group, change:
- Resource name from `linux_sg` to `blue_linux_sg`
- Add `provider = openstack.blue`

Update all rule resources similarly (change provider, update `security_group_id` references).

**Step 3: Add scoring security group**

Add after the blue security groups:

```hcl
# ==============================================================================
# SCORING SERVER SECURITY GROUP (Main Project)
# ==============================================================================

resource "openstack_networking_secgroup_v2" "scoring_sg" {
  provider    = openstack.main
  name        = "scoring-sg"
  description = "Security group for scoring servers"
}

resource "openstack_networking_secgroup_rule_v2" "scoring_ssh" {
  provider          = openstack.main
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.scoring_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "scoring_http" {
  provider          = openstack.main
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.scoring_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "scoring_https" {
  provider          = openstack.main
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.scoring_sg.id
}
```

**Step 4: Add red team security group**

```hcl
# ==============================================================================
# RED TEAM SECURITY GROUP (Red Project)
# ==============================================================================

resource "openstack_networking_secgroup_v2" "red_linux_sg" {
  provider    = openstack.red
  name        = "red-linux-sg"
  description = "Security group for Red Team Linux/Kali VMs"
}

resource "openstack_networking_secgroup_rule_v2" "red_ssh" {
  provider          = openstack.red
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.red_linux_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "red_rdp" {
  provider          = openstack.red
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.red_linux_sg.id
}
```

**Step 5: Validate syntax**

Run: `cd /root/cdt-automation/opentofu && tofu validate`
Expected: Errors about instance references (expected)

**Step 6: Commit**

```bash
git add opentofu/security.tf
git commit -m "feat(tofu): refactor security groups per project (scoring, blue, red)"
```

---

## Task 6: Refactor Instances - Blue Team VMs

**Files:**
- Modify: `opentofu/instances.tf`

**Step 1: Add Kali image data source**

Add after the existing image data sources (around line 43):

```hcl
data "openstack_images_image_v2" "kali" {
  name        = var.kali_image_name
  most_recent = true
}

data "openstack_images_image_v2" "scoring" {
  name        = var.scoring_image_name
  most_recent = true
}
```

**Step 2: Rename Windows VMs to Blue Windows**

Change the `openstack_compute_instance_v2.windows` resource:
- Rename to `blue_windows`
- Add `provider = openstack.blue`
- Update `count` to use `var.blue_windows_count`
- Update `name` to use `var.blue_windows_hostnames` and prefix `blue-win-`
- Update `security_groups` to reference `blue_windows_sg`

```hcl
resource "openstack_compute_instance_v2" "blue_windows" {
  provider = openstack.blue
  count    = var.blue_windows_count

  name = length(var.blue_windows_hostnames) > count.index ? var.blue_windows_hostnames[count.index] : "blue-win-${count.index + 1}"

  image_name      = var.windows_image_name
  flavor_name     = var.flavor_name
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.blue_windows_sg.name]

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.2${count.index + 1}"
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.windows.id
    source_type           = "image"
    volume_size           = 80
    destination_type      = "volume"
    delete_on_termination = true
  }

  user_data = file("${path.module}/windows-userdata.ps1")

  depends_on = [
    openstack_networking_rbac_policy_v2.share_with_blue
  ]
}
```

**Step 3: Rename Linux VMs to Blue Linux**

Change the `openstack_compute_instance_v2.debian` resource:
- Rename to `blue_linux`
- Add `provider = openstack.blue`
- Update `count` to use `var.blue_linux_count`
- Update `name` to use `var.blue_linux_hostnames` and prefix `blue-linux-`
- Update `security_groups` to reference `blue_linux_sg`

```hcl
resource "openstack_compute_instance_v2" "blue_linux" {
  provider = openstack.blue
  count    = var.blue_linux_count

  name = length(var.blue_linux_hostnames) > count.index ? var.blue_linux_hostnames[count.index] : "blue-linux-${count.index + 1}"

  image_name      = var.debian_image_name
  flavor_name     = var.flavor_name
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.blue_linux_sg.name]

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.3${count.index + 1}"
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.debian.id
    source_type           = "image"
    volume_size           = 80
    destination_type      = "volume"
    delete_on_termination = true
  }

  user_data = file("${path.module}/debian-userdata.yaml")

  depends_on = [
    openstack_networking_rbac_policy_v2.share_with_blue
  ]
}
```

**Step 4: Commit**

```bash
git add opentofu/instances.tf
git commit -m "feat(tofu): rename windows/debian VMs to blue_windows/blue_linux"
```

---

## Task 7: Add Scoring and Red Team VMs

**Files:**
- Modify: `opentofu/instances.tf`

**Step 1: Add scoring server instances**

Add after the blue_linux resource:

```hcl
# ==============================================================================
# SCORING SERVER (Main Project)
# ==============================================================================

resource "openstack_compute_instance_v2" "scoring" {
  provider = openstack.main
  count    = var.scoring_count

  name            = "scoring-${count.index + 1}"
  image_name      = var.scoring_image_name
  flavor_name     = var.flavor_name
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.scoring_sg.name]

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.1${count.index + 1}"
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.scoring.id
    source_type           = "image"
    volume_size           = 80
    destination_type      = "volume"
    delete_on_termination = true
  }

  user_data = file("${path.module}/debian-userdata.yaml")

  depends_on = []
}
```

**Step 2: Add red team Kali instances**

```hcl
# ==============================================================================
# RED TEAM KALI VMS (Red Project)
# ==============================================================================

resource "openstack_compute_instance_v2" "red_kali" {
  provider = openstack.red
  count    = var.red_kali_count

  name            = "red-kali-${count.index + 1}"
  image_name      = var.kali_image_name
  flavor_name     = var.flavor_name
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.red_linux_sg.name]

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.4${count.index + 1}"
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.kali.id
    source_type           = "image"
    volume_size           = 80
    destination_type      = "volume"
    delete_on_termination = true
  }

  user_data = file("${path.module}/debian-userdata.yaml")

  depends_on = [
    openstack_networking_rbac_policy_v2.share_with_red
  ]
}
```

**Step 3: Commit**

```bash
git add opentofu/instances.tf
git commit -m "feat(tofu): add scoring and red_kali VM resources"
```

---

## Task 8: Refactor Floating IPs and Associations

**Files:**
- Modify: `opentofu/instances.tf`

**Step 1: Update Blue Windows floating IPs**

Rename `win_fip` to `blue_win_fip` and add provider:

```hcl
resource "openstack_networking_floatingip_v2" "blue_win_fip" {
  provider = openstack.blue
  count    = var.blue_windows_count
  pool     = var.external_network
}
```

**Step 2: Update Blue Linux floating IPs**

Rename `debian_fip` to `blue_linux_fip` and add provider:

```hcl
resource "openstack_networking_floatingip_v2" "blue_linux_fip" {
  provider = openstack.blue
  count    = var.blue_linux_count
  pool     = var.external_network
}
```

**Step 3: Add scoring floating IPs**

```hcl
resource "openstack_networking_floatingip_v2" "scoring_fip" {
  provider = openstack.main
  count    = var.scoring_count
  pool     = var.external_network
}
```

**Step 4: Add red team floating IPs**

```hcl
resource "openstack_networking_floatingip_v2" "red_fip" {
  provider = openstack.red
  count    = var.red_kali_count
  pool     = var.external_network
}
```

**Step 5: Update port data sources**

Rename and add providers to all port data sources:

```hcl
data "openstack_networking_port_v2" "blue_win_port" {
  provider   = openstack.blue
  count      = var.blue_windows_count
  device_id  = openstack_compute_instance_v2.blue_windows[count.index].id
  network_id = openstack_networking_network_v2.cdt_net.id
}

data "openstack_networking_port_v2" "blue_linux_port" {
  provider   = openstack.blue
  count      = var.blue_linux_count
  device_id  = openstack_compute_instance_v2.blue_linux[count.index].id
  network_id = openstack_networking_network_v2.cdt_net.id
}

data "openstack_networking_port_v2" "scoring_port" {
  provider   = openstack.main
  count      = var.scoring_count
  device_id  = openstack_compute_instance_v2.scoring[count.index].id
  network_id = openstack_networking_network_v2.cdt_net.id
}

data "openstack_networking_port_v2" "red_port" {
  provider   = openstack.red
  count      = var.red_kali_count
  device_id  = openstack_compute_instance_v2.red_kali[count.index].id
  network_id = openstack_networking_network_v2.cdt_net.id
}
```

**Step 6: Update floating IP associations**

```hcl
resource "openstack_networking_floatingip_associate_v2" "blue_win_fip_assoc" {
  provider    = openstack.blue
  count       = var.blue_windows_count
  floating_ip = openstack_networking_floatingip_v2.blue_win_fip[count.index].address
  port_id     = data.openstack_networking_port_v2.blue_win_port[count.index].id
}

resource "openstack_networking_floatingip_associate_v2" "blue_linux_fip_assoc" {
  provider    = openstack.blue
  count       = var.blue_linux_count
  floating_ip = openstack_networking_floatingip_v2.blue_linux_fip[count.index].address
  port_id     = data.openstack_networking_port_v2.blue_linux_port[count.index].id
}

resource "openstack_networking_floatingip_associate_v2" "scoring_fip_assoc" {
  provider    = openstack.main
  count       = var.scoring_count
  floating_ip = openstack_networking_floatingip_v2.scoring_fip[count.index].address
  port_id     = data.openstack_networking_port_v2.scoring_port[count.index].id
}

resource "openstack_networking_floatingip_associate_v2" "red_fip_assoc" {
  provider    = openstack.red
  count       = var.red_kali_count
  floating_ip = openstack_networking_floatingip_v2.red_fip[count.index].address
  port_id     = data.openstack_networking_port_v2.red_port[count.index].id
}
```

**Step 7: Commit**

```bash
git add opentofu/instances.tf
git commit -m "feat(tofu): refactor floating IPs and associations for all teams"
```

---

## Task 9: Update Outputs

**Files:**
- Modify: `opentofu/outputs.tf`

**Step 1: Read current outputs.tf**

Run: `cat /root/cdt-automation/opentofu/outputs.tf`

**Step 2: Replace all outputs with team-organized outputs**

Replace the entire file with:

```hcl
# ==============================================================================
# OUTPUTS - Organized by Team
# ==============================================================================
# These outputs are consumed by import-tofu-to-ansible.py to generate inventory.

# ------------------------------------------------------------------------------
# SCORING SERVER OUTPUTS
# ------------------------------------------------------------------------------

output "scoring_names" {
  description = "Hostnames of scoring servers"
  value       = openstack_compute_instance_v2.scoring[*].name
}

output "scoring_ips" {
  description = "Internal IPs of scoring servers"
  value       = openstack_compute_instance_v2.scoring[*].network[0].fixed_ip_v4
}

output "scoring_floating_ips" {
  description = "Floating IPs of scoring servers"
  value       = openstack_networking_floatingip_v2.scoring_fip[*].address
}

# ------------------------------------------------------------------------------
# BLUE TEAM WINDOWS OUTPUTS
# ------------------------------------------------------------------------------

output "blue_windows_names" {
  description = "Hostnames of Blue Team Windows VMs"
  value       = openstack_compute_instance_v2.blue_windows[*].name
}

output "blue_windows_ips" {
  description = "Internal IPs of Blue Team Windows VMs"
  value       = openstack_compute_instance_v2.blue_windows[*].network[0].fixed_ip_v4
}

output "blue_windows_floating_ips" {
  description = "Floating IPs of Blue Team Windows VMs"
  value       = openstack_networking_floatingip_v2.blue_win_fip[*].address
}

# ------------------------------------------------------------------------------
# BLUE TEAM LINUX OUTPUTS
# ------------------------------------------------------------------------------

output "blue_linux_names" {
  description = "Hostnames of Blue Team Linux VMs"
  value       = openstack_compute_instance_v2.blue_linux[*].name
}

output "blue_linux_ips" {
  description = "Internal IPs of Blue Team Linux VMs"
  value       = openstack_compute_instance_v2.blue_linux[*].network[0].fixed_ip_v4
}

output "blue_linux_floating_ips" {
  description = "Floating IPs of Blue Team Linux VMs"
  value       = openstack_networking_floatingip_v2.blue_linux_fip[*].address
}

# ------------------------------------------------------------------------------
# RED TEAM OUTPUTS
# ------------------------------------------------------------------------------

output "red_kali_names" {
  description = "Hostnames of Red Team Kali VMs"
  value       = openstack_compute_instance_v2.red_kali[*].name
}

output "red_kali_ips" {
  description = "Internal IPs of Red Team Kali VMs"
  value       = openstack_compute_instance_v2.red_kali[*].network[0].fixed_ip_v4
}

output "red_kali_floating_ips" {
  description = "Floating IPs of Red Team Kali VMs"
  value       = openstack_networking_floatingip_v2.red_fip[*].address
}

# ------------------------------------------------------------------------------
# NETWORK OUTPUTS
# ------------------------------------------------------------------------------

output "network_id" {
  description = "ID of the shared network"
  value       = openstack_networking_network_v2.cdt_net.id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = openstack_networking_subnet_v2.cdt_subnet.id
}
```

**Step 3: Validate complete configuration**

Run: `cd /root/cdt-automation/opentofu && tofu validate`
Expected: Success with no errors

**Step 4: Commit**

```bash
git add opentofu/outputs.tf
git commit -m "feat(tofu): reorganize outputs by team for inventory generation"
```

---

## Task 10: Update Inventory Generator Script

**Files:**
- Modify: `import-tofu-to-ansible.py`

**Step 1: Read current script**

Run: `cat /root/cdt-automation/import-tofu-to-ansible.py`

**Step 2: Update the script to handle new output structure**

Key changes needed:
1. Read new output keys (scoring_*, blue_windows_*, blue_linux_*, red_kali_*)
2. Generate new inventory groups (scoring, windows_dc, blue_windows_members, blue_linux_members, red_team)
3. Generate group hierarchies (windows:children, blue_team:children, linux_members:children)

**Step 3: Test the script syntax**

Run: `python3 -m py_compile /root/cdt-automation/import-tofu-to-ansible.py`
Expected: No output (success)

**Step 4: Commit**

```bash
git add import-tofu-to-ansible.py
git commit -m "feat(inventory): update generator for multi-project team structure"
```

---

## Task 11: Validate Full Configuration

**Files:**
- All OpenTofu files

**Step 1: Initialize OpenTofu with new providers**

Run: `cd /root/cdt-automation && source app-cred-openrc.sh && cd opentofu && tofu init -upgrade`
Expected: Success, providers downloaded

**Step 2: Validate configuration**

Run: `tofu validate`
Expected: Success with no errors

**Step 3: Generate plan (dry run)**

Run: `tofu plan`
Expected: Plan shows resources to create across three projects

**Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "fix(tofu): address validation issues from full configuration test"
```

---

## Task 12: Update Documentation

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the IP Address Scheme section**

Find the "IP Address Scheme" section and update:

```markdown
### IP Address Scheme
- **Scoring VMs**: `10.10.10.11`, `10.10.10.12`, etc. (main project)
- **Blue Windows VMs**: `10.10.10.21`, `10.10.10.22`, `10.10.10.23` (first VM is DC)
- **Blue Linux VMs**: `10.10.10.31`, `10.10.10.32`, `10.10.10.33`, `10.10.10.34`
- **Red Kali VMs**: `10.10.10.41`, `10.10.10.42`, etc.
- All VMs get floating IPs for external access via SSH jump host
```

**Step 2: Add Multi-Project section**

Add a new section explaining the grey team setup.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for multi-project grey team deployment"
```

---

## Summary

This plan transforms the single-project deployment into a multi-project grey team infrastructure:

| Task | Description | Estimated Complexity |
|------|-------------|---------------------|
| 1 | Add project ID variables | Simple |
| 2 | Add VM count/image variables | Simple |
| 3 | Configure provider aliases | Simple |
| 4 | Add RBAC network sharing | Medium |
| 5 | Refactor security groups | Medium |
| 6 | Refactor blue team VMs | Medium |
| 7 | Add scoring/red team VMs | Medium |
| 8 | Refactor floating IPs | Medium |
| 9 | Update outputs | Simple |
| 10 | Update inventory generator | Medium |
| 11 | Validate full configuration | Simple |
| 12 | Update documentation | Simple |

**Migration Note:** Existing infrastructure must be destroyed before applying this configuration, as resource names and project assignments change significantly.
