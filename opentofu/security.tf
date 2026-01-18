# ==============================================================================
# SECURITY GROUPS (FIREWALL RULES)
# ==============================================================================
# Security groups act as virtual firewalls for your VMs.
# They control which network traffic is allowed in and out.
#
# HOW SECURITY GROUPS WORK:
# 1. Create a security group (a container for rules)
# 2. Add rules to allow specific traffic (everything else is denied)
# 3. Assign the security group to VMs
#
# DEFAULT BEHAVIOR:
# - All inbound traffic is DENIED unless a rule allows it
# - All outbound traffic is ALLOWED by default
# - Rules are stateful (responses to allowed outbound traffic are allowed in)
#
# MULTI-PROJECT CTF ARCHITECTURE:
# Security groups must be created in the SAME project as the VMs that use them.
# We can't share security groups across projects like we can with networks.
#
#   - MAIN project: scoring_sg (for scoring/monitoring VMs)
#   - BLUE project: blue_windows_sg, blue_linux_sg (for Blue Team VMs)
#   - RED project:  red_linux_sg (for Red Team Kali VMs)
#
# DOCUMENTATION:
# - Security Group: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_v2
# - Security Group Rule: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_rule_v2
#
# ==============================================================================


# ##############################################################################
#                         BLUE TEAM SECURITY GROUPS
# ##############################################################################
# These security groups live in the BLUE project and are assigned to Blue Team
# VMs. Blue Team defends these machines during the competition.

# ------------------------------------------------------------------------------
# BLUE TEAM - LINUX SECURITY GROUP
# ------------------------------------------------------------------------------
# Applied to Blue Team Linux VMs. Allows SSH and RDP (xRDP) access.

resource "openstack_networking_secgroup_v2" "blue_linux_sg" {
  provider = openstack.blue
  # PROVIDER EXPLAINED:
  # Security groups must live in the same project as the VMs that use them.
  # Blue Team VMs are in the "blue" project, so this security group must be too.

  name        = "blue-linux-sg"
  description = "Security group for Blue Team Linux VMs - allows SSH (22) and RDP (3389)"
}

# Allow SSH (port 22) from anywhere for Blue Team Linux VMs
resource "openstack_networking_secgroup_rule_v2" "blue_linux_ssh" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.blue_linux_sg.id

  # SSH = Secure Shell for remote command-line access
  # Blue Team uses this to manage their Linux servers
  # Red Team might try to brute-force or exploit SSH vulnerabilities!
}

# Allow RDP (port 3389) from anywhere for Blue Team Linux VMs (xRDP)
resource "openstack_networking_secgroup_rule_v2" "blue_linux_rdp" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.blue_linux_sg.id

  # xRDP provides graphical remote desktop access to Linux
  # Desktop environment: LXQT (pre-installed on Ubuntu2404Desktop)
}

# Allow all internal traffic for Blue Team Linux VMs
resource "openstack_networking_secgroup_rule_v2" "blue_linux_internal" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = ""                # Empty = all protocols
  remote_ip_prefix  = var.subnet_cidr   # Only from our subnet (10.10.10.0/24)
  security_group_id = openstack_networking_secgroup_v2.blue_linux_sg.id

  # WHY ALLOW ALL INTERNAL TRAFFIC:
  # In a CTF, VMs need to communicate for:
  # - Domain services (DNS, Kerberos, LDAP)
  # - Scoring checks (scoring server pings services)
  # - Red Team attacks (they're on the same network!)
  #
  # This means Blue Team must defend against attacks from 10.10.10.0/24
}

# ------------------------------------------------------------------------------
# BLUE TEAM - WINDOWS SECURITY GROUP
# ------------------------------------------------------------------------------
# Applied to Blue Team Windows VMs (Domain Controller and members).
# Allows WinRM (for Ansible) and RDP access.

resource "openstack_networking_secgroup_v2" "blue_windows_sg" {
  provider    = openstack.blue
  name        = "blue-windows-sg"
  description = "Security group for Blue Team Windows VMs - WinRM (5985/5986) and RDP (3389)"
}

# Allow WinRM HTTP (port 5985) for Windows configuration via Ansible
resource "openstack_networking_secgroup_rule_v2" "blue_windows_winrm_http" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5985
  port_range_max    = 5985
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.blue_windows_sg.id

  # WinRM = Windows Remote Management
  # Used by Ansible to configure Windows VMs
  # Port 5985 is unencrypted - OK for lab, not production
}

# Allow WinRM HTTPS (port 5986) for secure Windows management
resource "openstack_networking_secgroup_rule_v2" "blue_windows_winrm_https" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5986
  port_range_max    = 5986
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.blue_windows_sg.id
}

# Allow RDP (port 3389) for graphical Windows access
resource "openstack_networking_secgroup_rule_v2" "blue_windows_rdp" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.blue_windows_sg.id

  # RDP = Remote Desktop Protocol
  # Blue Team uses this to manage Windows servers
  # Connect via: mstsc /v:<floating_ip>
}

# Allow all internal traffic for Blue Team Windows VMs
resource "openstack_networking_secgroup_rule_v2" "blue_windows_internal" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = ""
  remote_ip_prefix  = var.subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.blue_windows_sg.id

  # COMMON WINDOWS PORTS (all covered by this rule):
  # - DNS: 53 (TCP/UDP)
  # - Kerberos: 88 (TCP/UDP) - Active Directory authentication
  # - LDAP: 389 (TCP/UDP) - Directory services
  # - SMB: 445 (TCP) - File sharing
  # - Active Directory GC: 3268, 3269 (TCP)
  #
  # Red Team will probe all of these looking for vulnerabilities!
}


# ##############################################################################
#                         SCORING SECURITY GROUP (Main Project)
# ##############################################################################
# Scoring VMs live in the MAIN project. They monitor Blue Team services
# and determine scores. These should be well-protected from Red Team.

resource "openstack_networking_secgroup_v2" "scoring_sg" {
  provider    = openstack.main
  name        = "scoring-sg"
  description = "Security group for scoring/Grey Team servers"

  # GREY TEAM / SCORING:
  # In a CCDC-style competition, Grey Team runs the infrastructure:
  # - Scoring engine that checks if services are up
  # - Monitoring/logging servers
  # - Competition infrastructure
  #
  # Grey Team is neutral - they run the game, not playing it
}

# Allow SSH for scoring server management
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

# Allow HTTP for scoring web interface
resource "openstack_networking_secgroup_rule_v2" "scoring_http" {
  provider          = openstack.main
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.scoring_sg.id

  # Scoring dashboard - shows team scores during competition
}

# Allow HTTPS for secure scoring web interface
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

# Allow RDP for scoring server GUI access
resource "openstack_networking_secgroup_rule_v2" "scoring_rdp" {
  provider          = openstack.main
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.scoring_sg.id
}

# Allow all internal traffic for scoring (to reach Blue Team services)
resource "openstack_networking_secgroup_rule_v2" "scoring_internal" {
  provider          = openstack.main
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = ""
  remote_ip_prefix  = var.subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.scoring_sg.id

  # Scoring engine needs to check services on Blue Team VMs
  # It will ping, HTTP, SSH, etc. to verify services are running
}


# ##############################################################################
#                         RED TEAM SECURITY GROUP
# ##############################################################################
# Red Team Kali VMs live in the RED project. These are the attack machines
# used to compromise Blue Team infrastructure.

resource "openstack_networking_secgroup_v2" "red_linux_sg" {
  provider    = openstack.red
  name        = "red-linux-sg"
  description = "Security group for Red Team Kali attack VMs"

  # RED TEAM:
  # These are the "bad guys" in the competition (played by students/staff).
  # They try to:
  # - Find vulnerabilities in Blue Team services
  # - Exploit and gain access to Blue Team VMs
  # - Maintain persistence (stay hidden)
  # - Exfiltrate "flags" for points
  #
  # Kali Linux comes pre-loaded with hacking tools:
  # - Nmap (network scanning)
  # - Metasploit (exploitation framework)
  # - Burp Suite (web app testing)
  # - John the Ripper (password cracking)
  # And hundreds more!
}

# Allow SSH for Red Team to access their Kali VMs
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

# Allow RDP for Red Team GUI access to Kali
resource "openstack_networking_secgroup_rule_v2" "red_rdp" {
  provider          = openstack.red
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.red_linux_sg.id

  # Kali with GUI is useful for:
  # - Burp Suite (needs browser)
  # - Wireshark (packet analysis)
  # - BloodHound (AD attack path visualization)
}

# Allow all internal traffic for Red Team (to attack Blue Team!)
resource "openstack_networking_secgroup_rule_v2" "red_internal" {
  provider          = openstack.red
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = ""
  remote_ip_prefix  = var.subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.red_linux_sg.id

  # Red Team needs unrestricted access to the internal network
  # They'll scan, probe, and exploit everything they can find!
}


# ==============================================================================
# SECURITY GROUP SUMMARY FOR CTF
# ==============================================================================
#
#                    +-----------------+
#                    |   MAIN PROJECT  |
#                    |   scoring_sg    |
#                    | (Grey Team VMs) |
#                    +-------+---------+
#                            |
#          +-----------------+------------------+
#          |                                    |
#  +-------+--------+                  +--------+-------+
#  |  BLUE PROJECT  |                  |  RED PROJECT   |
#  | blue_linux_sg  |                  |  red_linux_sg  |
#  | blue_windows_sg|                  |  (Kali VMs)    |
#  | (Defender VMs) |                  |  (Attacker VMs)|
#  +----------------+                  +----------------+
#
# All VMs are on the same network (10.10.10.0/24) via RBAC sharing.
# Red Team attacks Blue Team. Scoring monitors everything.
#
# TYPICAL CTF ATTACK FLOW:
# 1. Red Team scans Blue Team IPs with Nmap
# 2. Red Team finds vulnerable service (old SSH, unpatched web app, etc.)
# 3. Red Team exploits vulnerability to gain access
# 4. Blue Team should detect and block the attack
# 5. Scoring engine checks: Is the service still up? Blue Team gets points!
#
# ==============================================================================

# ==============================================================================
# ADDING RULES FOR YOUR COMPETITION
# ==============================================================================
#
# COMMON PORTS YOU MIGHT NEED FOR BLUE TEAM SERVICES:
#
# WEB SERVER (if Blue Team runs a website to defend):
# resource "openstack_networking_secgroup_rule_v2" "blue_linux_http" {
#   provider          = openstack.blue
#   direction         = "ingress"
#   ethertype         = "IPv4"
#   protocol          = "tcp"
#   port_range_min    = 80
#   port_range_max    = 80
#   remote_ip_prefix  = "0.0.0.0/0"
#   security_group_id = openstack_networking_secgroup_v2.blue_linux_sg.id
# }
#
# DATABASE (internal access only - don't expose to internet!):
# resource "openstack_networking_secgroup_rule_v2" "blue_linux_mysql" {
#   provider          = openstack.blue
#   direction         = "ingress"
#   ethertype         = "IPv4"
#   protocol          = "tcp"
#   port_range_min    = 3306
#   port_range_max    = 3306
#   remote_ip_prefix  = var.subnet_cidr  # Only internal!
#   security_group_id = openstack_networking_secgroup_v2.blue_linux_sg.id
# }
#
# EMAIL SERVER:
# resource "openstack_networking_secgroup_rule_v2" "blue_linux_smtp" {
#   provider          = openstack.blue
#   direction         = "ingress"
#   ethertype         = "IPv4"
#   protocol          = "tcp"
#   port_range_min    = 25
#   port_range_max    = 25
#   remote_ip_prefix  = "0.0.0.0/0"
#   security_group_id = openstack_networking_secgroup_v2.blue_linux_sg.id
# }
#
# ==============================================================================
