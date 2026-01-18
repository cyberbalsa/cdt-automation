# ==============================================================================
# OUTPUTS - Organized by Team
# ==============================================================================
# Outputs display useful information after 'tofu apply' completes.
# They also make values available to other tools (like our Python script).
#
# HOW OUTPUTS WORK:
# - Defined here, displayed after apply
# - View anytime with: tofu output
# - Get JSON format with: tofu output -json
# - Access specific output: tofu output blue_windows_names
#
# WHY OUTPUTS MATTER FOR CTF:
# - See all VM IPs without opening OpenStack dashboard
# - Pass information to Ansible for automated configuration
# - Quick reference during competition for scoring checks
# - Essential for the inventory generator script
#
# OUTPUT ORGANIZATION:
# We organize outputs by team to match the CTF structure:
#   1. Scoring (Grey Team) - Competition infrastructure
#   2. Blue Team Windows - Domain Controller and member servers
#   3. Blue Team Linux - Web servers, databases, etc.
#   4. Red Team - Kali attack machines
#   5. Network - Shared infrastructure IDs
#
# DOCUMENTATION:
# - OpenTofu Outputs: https://opentofu.org/docs/language/values/outputs/
# - Terraform Outputs: https://developer.hashicorp.com/terraform/language/values/outputs
#
# ==============================================================================


# ##############################################################################
#                         SCORING SERVER OUTPUTS (Grey Team)
# ##############################################################################
# Grey Team runs the competition: scoring engine, monitoring, infrastructure.
# These outputs help Grey Team manage the scoring servers.

output "scoring_names" {
  description = "Hostnames of scoring servers"
  value       = openstack_compute_instance_v2.scoring[*].name
  # SPLAT EXPRESSION EXPLAINED:
  # [*] is shorthand for "get this attribute from ALL items in the list"
  # Equivalent to: [for vm in openstack_compute_instance_v2.scoring : vm.name]
  #
  # Result: ["scoring-1"]
}

output "scoring_ips" {
  description = "Internal IPs of scoring servers"
  value       = openstack_compute_instance_v2.scoring[*].network[0].fixed_ip_v4
  # Gets the fixed IP from the first (index 0) network of each VM
  #
  # Result: ["10.10.10.11"]
  #
  # GREY TEAM TIP:
  # The scoring server needs to reach all Blue Team services to check uptime.
  # It will ping, HTTP, SSH, etc. to verify services are running.
}

output "scoring_floating_ips" {
  description = "Floating IPs of scoring servers"
  value       = openstack_networking_floatingip_v2.scoring_fip[*].address
  # Result: ["100.65.x.x"]
  #
  # ACCESS SCORING SERVER:
  # ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<floating_ip>
}


# ##############################################################################
#                         BLUE TEAM WINDOWS OUTPUTS
# ##############################################################################
# Blue Team Windows VMs: Domain Controller (first VM) and member servers.
# Blue Team defends these against Red Team attacks.

output "blue_windows_names" {
  description = "Hostnames of Blue Team Windows VMs"
  value       = openstack_compute_instance_v2.blue_windows[*].name
  # Result: ["dc01", "blue-win-2"] (depends on blue_windows_hostnames variable)
  #
  # FIRST VM IS ALWAYS THE DOMAIN CONTROLLER!
  # Ansible uses this convention to set up Active Directory.
}

output "blue_windows_ips" {
  description = "Internal IPs of Blue Team Windows VMs"
  value       = openstack_compute_instance_v2.blue_windows[*].network[0].fixed_ip_v4
  # Result: ["10.10.10.21", "10.10.10.22"]
  #
  # BLUE TEAM DEFENSE TIPS:
  # - Monitor these IPs for suspicious connections from 10.10.10.4x (Red Team)
  # - Check Windows Event Logs for failed login attempts
  # - Watch for unusual processes or services
}

output "blue_windows_floating_ips" {
  description = "Floating IPs of Blue Team Windows VMs"
  value       = openstack_networking_floatingip_v2.blue_win_fip[*].address
  # Result: ["100.65.x.x", "100.65.x.x"]
  #
  # ACCESS BLUE WINDOWS VMs:
  # RDP: Create SSH tunnel first:
  #   ssh -L 3389:<floating_ip>:3389 sshjump@ssh.cyberrange.rit.edu
  # Then connect RDP to: localhost:3389
}


# ##############################################################################
#                         BLUE TEAM LINUX OUTPUTS
# ##############################################################################
# Blue Team Linux VMs: web servers, databases, application servers.
# These join the Windows domain and are defended by Blue Team.

output "blue_linux_names" {
  description = "Hostnames of Blue Team Linux VMs"
  value       = openstack_compute_instance_v2.blue_linux[*].name
  # Result: ["webserver", "blue-linux-2"]
}

output "blue_linux_ips" {
  description = "Internal IPs of Blue Team Linux VMs"
  value       = openstack_compute_instance_v2.blue_linux[*].network[0].fixed_ip_v4
  # Result: ["10.10.10.31", "10.10.10.32"]
  #
  # BLUE TEAM DEFENSE TIPS:
  # - Check /var/log/auth.log for SSH brute force attempts
  # - Monitor web server logs for SQL injection, XSS attempts
  # - Use 'netstat -tulpn' to see what ports are exposed
  # - Run 'ps aux' to check for suspicious processes
}

output "blue_linux_floating_ips" {
  description = "Floating IPs of Blue Team Linux VMs"
  value       = openstack_networking_floatingip_v2.blue_linux_fip[*].address
  # Result: ["100.65.x.x", "100.65.x.x"]
  #
  # ACCESS BLUE LINUX VMs:
  # SSH: ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<floating_ip>
  # RDP (xRDP): Same tunnel method as Windows
}


# ##############################################################################
#                         RED TEAM OUTPUTS
# ##############################################################################
# Red Team Kali VMs: attack machines loaded with penetration testing tools.
# Red Team uses these to compromise Blue Team infrastructure.

output "red_kali_names" {
  description = "Hostnames of Red Team Kali VMs"
  value       = openstack_compute_instance_v2.red_kali[*].name
  # Result: ["red-kali-1", "red-kali-2"]
}

output "red_kali_ips" {
  description = "Internal IPs of Red Team Kali VMs"
  value       = openstack_compute_instance_v2.red_kali[*].network[0].fixed_ip_v4
  # Result: ["10.10.10.41", "10.10.10.42"]
  #
  # RED TEAM ATTACK TIPS:
  # From Kali, you can reach all Blue Team VMs:
  #   nmap -sV 10.10.10.21-39    # Scan Blue Team IP range
  #   nmap -sC -sV 10.10.10.21   # Detailed scan of DC
  #
  # Common attack vectors:
  # - SMB vulnerabilities (EternalBlue, PrintNightmare)
  # - Kerberoasting (extract service account hashes)
  # - Web app vulnerabilities (SQLi, RCE)
  # - Weak passwords on SSH/RDP
}

output "red_kali_floating_ips" {
  description = "Floating IPs of Red Team Kali VMs"
  value       = openstack_networking_floatingip_v2.red_fip[*].address
  # Result: ["100.65.x.x", "100.65.x.x"]
  #
  # ACCESS KALI VMs:
  # SSH: ssh -J sshjump@ssh.cyberrange.rit.edu kali@<floating_ip>
  # RDP: Use tunnel for graphical tools (Burp Suite, BloodHound)
}


# ##############################################################################
#                         NETWORK OUTPUTS
# ##############################################################################
# Information about the shared network infrastructure.

output "network_id" {
  description = "ID of the shared network"
  value       = openstack_networking_network_v2.cdt_net.id
  # Used internally by OpenStack to identify the network
  # Useful for debugging or adding more VMs manually
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = openstack_networking_subnet_v2.cdt_subnet.id
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = openstack_networking_subnet_v2.cdt_subnet.cidr
  # Result: "10.10.10.0/24"
  #
  # This is the IP range all VMs share. Since Red Team is on the same
  # network as Blue Team, they can directly attack each other!
}


# ##############################################################################
#                         QUICK REFERENCE OUTPUTS
# ##############################################################################
# Convenient outputs for common tasks during competition.

output "domain_controller_ip" {
  description = "Internal IP of the Domain Controller (first Blue Windows VM)"
  value       = var.blue_windows_count > 0 ? openstack_compute_instance_v2.blue_windows[0].network[0].fixed_ip_v4 : null
  # CONDITIONAL OUTPUT:
  # condition ? value_if_true : value_if_false
  # Returns null if no Windows VMs exist (edge case)
  #
  # Result: "10.10.10.21"
  #
  # IMPORTANT FOR CTF:
  # All domain-joined VMs use this IP for:
  # - DNS resolution (CDT.local domain)
  # - Authentication (Kerberos)
  # - Group Policy
}

output "domain_controller_floating_ip" {
  description = "Floating IP of the Domain Controller"
  value       = var.blue_windows_count > 0 ? openstack_networking_floatingip_v2.blue_win_fip[0].address : null
  # Result: "100.65.x.x"
  #
  # USE THIS TO:
  # - RDP into DC for Active Directory management
  # - Troubleshoot domain issues
  # - Check Event Viewer for attack indicators
}


# ==============================================================================
# EXAMPLE OUTPUT AFTER 'tofu apply'
# ==============================================================================
#
# After running 'tofu apply', you'll see something like:
#
#   Apply complete! Resources: 15 added, 0 changed, 0 destroyed.
#
#   Outputs:
#
#   blue_linux_floating_ips = [
#     "100.65.4.61",
#     "100.65.4.62",
#   ]
#   blue_linux_ips = [
#     "10.10.10.31",
#     "10.10.10.32",
#   ]
#   blue_linux_names = [
#     "webserver",
#     "blue-linux-2",
#   ]
#   blue_windows_floating_ips = [
#     "100.65.4.51",
#     "100.65.4.52",
#   ]
#   blue_windows_ips = [
#     "10.10.10.21",
#     "10.10.10.22",
#   ]
#   blue_windows_names = [
#     "dc01",
#     "blue-win-2",
#   ]
#   domain_controller_floating_ip = "100.65.4.51"
#   domain_controller_ip = "10.10.10.21"
#   red_kali_floating_ips = [
#     "100.65.4.71",
#     "100.65.4.72",
#   ]
#   red_kali_ips = [
#     "10.10.10.41",
#     "10.10.10.42",
#   ]
#   red_kali_names = [
#     "red-kali-1",
#     "red-kali-2",
#   ]
#   scoring_floating_ips = [
#     "100.65.4.11",
#   ]
#   scoring_ips = [
#     "10.10.10.11",
#   ]
#   scoring_names = [
#     "scoring-1",
#   ]
#
# ==============================================================================
# HOW THE INVENTORY SCRIPT USES THESE OUTPUTS
# ==============================================================================
#
# The import-tofu-to-ansible.py script runs 'tofu output -json' and parses
# this data to create the Ansible inventory. It maps:
#
#   OpenTofu Output          ->  Ansible Inventory Group
#   ----------------             ----------------------
#   scoring_*                ->  [scoring]
#   blue_windows_* (first)   ->  [windows_dc]
#   blue_windows_* (rest)    ->  [blue_windows_members]
#   blue_linux_*             ->  [blue_linux_members]
#   red_kali_*               ->  [red_team]
#
# This allows Ansible to run different playbooks for different teams!
#
# ==============================================================================
