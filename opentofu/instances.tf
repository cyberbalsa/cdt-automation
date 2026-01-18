# ==============================================================================
# COMPUTE INSTANCES (VIRTUAL MACHINES)
# ==============================================================================
# This file creates the virtual machines in OpenStack.
# It also assigns floating IPs so you can access them from outside.
#
# MULTI-PROJECT CTF ARCHITECTURE:
# VMs are deployed to different OpenStack projects based on their role:
#
#   MAIN PROJECT (Grey Team):
#   - Scoring servers (monitor Blue Team services)
#
#   BLUE PROJECT (Defenders):
#   - Windows Domain Controller (first Windows VM)
#   - Windows member servers
#   - Linux servers (web, database, etc.)
#
#   RED PROJECT (Attackers):
#   - Kali Linux attack machines
#
# All VMs connect to the SAME network (shared via RBAC) so Red can attack Blue!
#
# DOCUMENTATION:
# - Compute Instance: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_instance_v2
# - Floating IP: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_floatingip_v2
# - Images Data Source: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/images_image_v2
#
# ==============================================================================


# ##############################################################################
#                         IMAGE DATA SOURCES
# ##############################################################################
# These data sources find the image IDs for each OS type.
# Images must exist in OpenStack before you can use them.

data "openstack_images_image_v2" "windows" {
  name        = var.windows_image_name    # "WindowsServer2022"
  most_recent = true
  # Returns: data.openstack_images_image_v2.windows.id
}

data "openstack_images_image_v2" "debian" {
  name        = var.debian_image_name     # "Ubuntu2404Desktop"
  most_recent = true
  # Used for Blue Team Linux servers
}

data "openstack_images_image_v2" "scoring" {
  name        = var.scoring_image_name    # "Ubuntu2404Desktop"
  most_recent = true
  # Used for scoring/Grey Team servers
}

data "openstack_images_image_v2" "kali" {
  name        = var.kali_image_name       # "kali-2024"
  most_recent = true
  # Used for Red Team attack VMs
  #
  # KALI LINUX:
  # Pre-loaded with penetration testing tools:
  # - Nmap, Metasploit, Burp Suite, Wireshark
  # - Password crackers, exploit frameworks
  # - Perfect for Red Team operations!
}


# ##############################################################################
#                         BLUE TEAM WINDOWS VMS
# ##############################################################################
# Windows VMs for Blue Team to defend. The FIRST VM becomes the Domain Controller.
# These live in the BLUE project.

resource "openstack_compute_instance_v2" "blue_windows" {
  provider = openstack.blue
  # PROVIDER EXPLAINED:
  # This VM is created in the Blue Team's OpenStack project.
  # Blue Team members can see and manage it in their dashboard.
  # Red Team CANNOT see this VM in their dashboard - only network traffic!

  count = var.blue_windows_count
  # count = 2 creates: blue_windows[0] (DC), blue_windows[1] (member)

  name = length(var.blue_windows_hostnames) > count.index ? var.blue_windows_hostnames[count.index] : "blue-win-${count.index + 1}"
  # CONDITIONAL NAMING:
  # If custom hostname provided, use it; otherwise auto-generate
  # Example: hostnames = ["dc01"] with count = 2
  #   VM 0: "dc01" (custom)
  #   VM 1: "blue-win-2" (auto)

  image_name      = var.windows_image_name
  flavor_name     = var.flavor_name
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.blue_windows_sg.name]
  # Uses Blue Team Windows security group (WinRM, RDP)

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    # Connects to the shared network (owned by main, shared via RBAC)
    fixed_ip_v4 = "10.10.10.2${count.index + 1}"
    # Blue Windows IPs: 10.10.10.21, 10.10.10.22, 10.10.10.23...
    # IP SCHEME:
    #   10.10.10.1x = Scoring (Grey Team)
    #   10.10.10.2x = Blue Windows
    #   10.10.10.3x = Blue Linux
    #   10.10.10.4x = Red Team Kali
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.windows.id
    source_type           = "image"
    volume_size           = 80
    destination_type      = "volume"
    delete_on_termination = true
  }

  user_data = file("${path.module}/windows-userdata.ps1")
  # PowerShell script that enables WinRM for Ansible management

  depends_on = [
    openstack_networking_rbac_policy_v2.share_with_blue
    # DEPENDENCY EXPLAINED:
    # The network must be shared with Blue project BEFORE creating VMs
    # Otherwise, Blue project VMs can't connect to the network!
  ]
}


# ##############################################################################
#                         BLUE TEAM LINUX VMS
# ##############################################################################
# Linux VMs for Blue Team to defend (web servers, databases, etc.)
# These join the Windows domain via Ansible.

resource "openstack_compute_instance_v2" "blue_linux" {
  provider = openstack.blue

  count = var.blue_linux_count

  name = length(var.blue_linux_hostnames) > count.index ? var.blue_linux_hostnames[count.index] : "blue-linux-${count.index + 1}"

  image_name      = var.debian_image_name
  flavor_name     = var.flavor_name
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.blue_linux_sg.name]
  # Uses Blue Team Linux security group (SSH, RDP)

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.3${count.index + 1}"
    # Blue Linux IPs: 10.10.10.31, 10.10.10.32, 10.10.10.33...
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.debian.id
    source_type           = "image"
    volume_size           = 80
    destination_type      = "volume"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/debian-userdata.sh", {
    instance_num = count.index + 1
  })
  # CLOUD-INIT USER DATA:
  # This bash script runs on first boot to configure the VM.
  # It creates the cyberrange user and enables SSH password auth.
  #
  # TEMPLATEFILE EXPLAINED:
  # templatefile() reads a file and replaces variables like ${instance_num}
  # with actual values. Each VM gets its own instance number (1, 2, 3...).
  #
  # The script writes the instance number to /etc/goad/instance_num
  # which Ansible can read later for VM-specific configuration.

  depends_on = [
    openstack_networking_rbac_policy_v2.share_with_blue
  ]
}


# ##############################################################################
#                         SCORING VMS (Grey Team)
# ##############################################################################
# Scoring servers that monitor Blue Team services and calculate scores.
# These live in the MAIN project and are managed by Grey Team.

resource "openstack_compute_instance_v2" "scoring" {
  provider = openstack.main

  count = var.scoring_count

  name            = "scoring-${count.index + 1}"
  image_name      = var.scoring_image_name
  flavor_name     = var.flavor_name
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.scoring_sg.name]

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.1${count.index + 1}"
    # Scoring IPs: 10.10.10.11, 10.10.10.12...
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.scoring.id
    source_type           = "image"
    volume_size           = 80
    destination_type      = "volume"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/debian-userdata.sh", {
    instance_num = count.index + 1
  })
  # Same cloud-init script as Blue Linux VMs.
  # Scoring servers need the cyberrange user for Ansible access.

  # SCORING ENGINE:
  # This VM runs the scoring software that:
  # 1. Periodically checks if Blue Team services are up (HTTP, SSH, etc.)
  # 2. Awards points for uptime
  # 3. Displays scoreboard for all teams
  #
  # Popular scoring engines:
  # - ScoringEngine (https://github.com/scoringengine/scoringengine)
  # - Aeolus (used by National CCDC)
  # - Custom solutions

  depends_on = []
}


# ##############################################################################
#                         RED TEAM KALI VMS
# ##############################################################################
# Kali Linux attack VMs for Red Team. Used to compromise Blue Team infrastructure.
# These live in the RED project.

resource "openstack_compute_instance_v2" "red_kali" {
  provider = openstack.red

  count = var.red_kali_count

  name            = "red-kali-${count.index + 1}"
  image_name      = var.kali_image_name
  flavor_name     = var.flavor_name
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.red_linux_sg.name]

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.4${count.index + 1}"
    # Red Team IPs: 10.10.10.41, 10.10.10.42...
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.kali.id
    source_type           = "image"
    volume_size           = 80
    destination_type      = "volume"
    delete_on_termination = true
  }

  user_data = file("${path.module}/kali-userdata.sh")
  # Kali uses a bash script for more robust package installation
  # Installs xRDP with XFCE desktop for GUI access

  depends_on = [
    openstack_networking_rbac_policy_v2.share_with_red
    # Network must be shared with Red project first
  ]

  # RED TEAM ATTACK WORKFLOW:
  # 1. Log into Kali VM via SSH or RDP
  # 2. Scan Blue Team IPs: nmap -sV 10.10.10.21-39
  # 3. Find vulnerable services
  # 4. Exploit and gain access
  # 5. Capture flags, maintain persistence
  #
  # Blue Team should be monitoring for these attacks!
}


# ##############################################################################
#                         FLOATING IPS (Public Access)
# ##############################################################################
# Floating IPs are public addresses that let you access VMs from outside.
# Each team's VMs get floating IPs from their respective project's quota.

# Blue Team Windows floating IPs
resource "openstack_networking_floatingip_v2" "blue_win_fip" {
  provider = openstack.blue
  count    = var.blue_windows_count
  pool     = var.external_network
}

# Blue Team Linux floating IPs
resource "openstack_networking_floatingip_v2" "blue_linux_fip" {
  provider = openstack.blue
  count    = var.blue_linux_count
  pool     = var.external_network
}

# Scoring server floating IPs
resource "openstack_networking_floatingip_v2" "scoring_fip" {
  provider = openstack.main
  count    = var.scoring_count
  pool     = var.external_network
}

# Red Team floating IPs
resource "openstack_networking_floatingip_v2" "red_fip" {
  provider = openstack.red
  count    = var.red_kali_count
  pool     = var.external_network
}


# ##############################################################################
#                         PORT DATA SOURCES
# ##############################################################################
# To associate floating IPs with VMs, we need each VM's network port ID.

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


# ##############################################################################
#                         FLOATING IP ASSOCIATIONS
# ##############################################################################
# Links floating IPs to VM ports so external traffic reaches the VMs.

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


# ==============================================================================
# IP ADDRESS SUMMARY
# ==============================================================================
#
#   10.10.10.11-19  =  Scoring/Grey Team (main project)
#   10.10.10.21-29  =  Blue Team Windows (blue project)
#   10.10.10.31-39  =  Blue Team Linux (blue project)
#   10.10.10.41-49  =  Red Team Kali (red project)
#
# All VMs share the same 10.10.10.0/24 network via RBAC sharing.
# Each VM also gets a floating IP (100.65.x.x) for external access.
#
# ==============================================================================
# CTF ATTACK SCENARIO
# ==============================================================================
#
#   +-----------------+     Network Traffic     +-----------------+
#   |   RED TEAM      |  ===================>   |   BLUE TEAM     |
#   |   10.10.10.4x   |                         |   10.10.10.2x   |
#   |   (Kali VMs)    |                         |   10.10.10.3x   |
#   +-----------------+                         +-----------------+
#           ^                                           |
#           |              +-----------------+          |
#           +--------------+   SCORING       +----------+
#                          |   10.10.10.1x   |
#                          |   (monitors)    |
#                          +-----------------+
#
# Red attacks Blue. Scoring monitors. Blue defends and keeps services up!
#
# ==============================================================================
