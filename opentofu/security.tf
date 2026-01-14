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
# DOCUMENTATION:
# - Security Group: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_v2
# - Security Group Rule: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_rule_v2
#
# ==============================================================================

# ------------------------------------------------------------------------------
# LINUX SECURITY GROUP
# ------------------------------------------------------------------------------
# Applied to all Linux VMs. Allows SSH and RDP (xRDP) access.
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_v2

resource "openstack_networking_secgroup_v2" "linux_sg" {
  name        = "cdt-linux-sg"
  description = "Security group for Linux VMs - allows SSH (22) and RDP (3389)"

  # ATTRIBUTES EXPLAINED:
  # - name: Identifier shown in OpenStack dashboard
  # - description: Human-readable explanation
  #
  # After creation, add rules (below) to allow specific traffic
}

# ------------------------------------------------------------------------------
# WINDOWS SECURITY GROUP
# ------------------------------------------------------------------------------
# Applied to all Windows VMs. Allows WinRM and RDP access.
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_v2

resource "openstack_networking_secgroup_v2" "windows_sg" {
  name        = "cdt-windows-sg"
  description = "Security group for Windows VMs - allows WinRM (5985/5986) and RDP (3389)"
}

# ==============================================================================
# LINUX SECURITY GROUP RULES
# ==============================================================================
# Each rule allows specific traffic through the firewall.
#
# RULE ATTRIBUTES:
# - direction: "ingress" (inbound) or "egress" (outbound)
# - ethertype: "IPv4" or "IPv6"
# - protocol: "tcp", "udp", "icmp", or "" (all protocols)
# - port_range_min/max: Port range to allow (same number for single port)
# - remote_ip_prefix: Source IP range (0.0.0.0/0 = anywhere)
# - security_group_id: Which security group this rule belongs to
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_rule_v2
# ==============================================================================

# Allow SSH (port 22) from anywhere for Linux VMs
# SSH = Secure Shell, used for remote command-line access
resource "openstack_networking_secgroup_rule_v2" "ssh_ingress" {
  direction         = "ingress"         # Inbound traffic
  ethertype         = "IPv4"            # IPv4 addresses
  protocol          = "tcp"             # TCP protocol (SSH uses TCP)
  port_range_min    = 22                # Port 22
  port_range_max    = 22                # Single port (min = max)
  remote_ip_prefix  = "0.0.0.0/0"       # From any IP address
  security_group_id = openstack_networking_secgroup_v2.linux_sg.id

  # SECURITY NOTE:
  # 0.0.0.0/0 allows connections from anywhere - OK for labs
  # In production, restrict to specific IPs or ranges
  # Example: "100.65.0.0/16" to only allow from MAIN-NAT
}

# Allow RDP (port 3389) from anywhere for Linux VMs (xRDP)
# xRDP provides graphical remote desktop access to Linux
resource "openstack_networking_secgroup_rule_v2" "linux_rdp_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389              # Standard RDP port
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.linux_sg.id

  # Linux uses xRDP to accept RDP connections
  # Desktop environment: LXQT (pre-installed on Ubuntu2404Desktop)
}

# ==============================================================================
# WINDOWS SECURITY GROUP RULES
# ==============================================================================

# Allow WinRM HTTP (port 5985) from anywhere for Windows VMs
# WinRM = Windows Remote Management, used by Ansible to configure Windows
resource "openstack_networking_secgroup_rule_v2" "winrm_http_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5985              # WinRM HTTP port
  port_range_max    = 5985
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.windows_sg.id

  # WinRM HTTP is unencrypted - OK for isolated lab networks
  # For production, use WinRM HTTPS (port 5986) only
}

# Allow WinRM HTTPS (port 5986) from anywhere for Windows VMs
# Encrypted version of WinRM for secure management
resource "openstack_networking_secgroup_rule_v2" "winrm_https_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5986              # WinRM HTTPS port
  port_range_max    = 5986
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.windows_sg.id
}

# Allow RDP (port 3389) from anywhere for Windows VMs
# RDP = Remote Desktop Protocol, graphical access to Windows
resource "openstack_networking_secgroup_rule_v2" "rdp_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389              # Standard RDP port
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.windows_sg.id

  # RDP provides full graphical desktop access
  # Connect via: mstsc /v:<floating_ip>:3389
}

# ==============================================================================
# INTERNAL NETWORK RULES
# ==============================================================================
# Allow all traffic between VMs on the same network.
# This is needed for domain services, file sharing, etc.

# Allow all internal traffic for Linux VMs
resource "openstack_networking_secgroup_rule_v2" "linux_internal_all" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = ""                # Empty string = all protocols
  remote_ip_prefix  = var.subnet_cidr   # Only from our subnet (10.10.10.0/24)
  security_group_id = openstack_networking_secgroup_v2.linux_sg.id

  # WHY ALLOW ALL INTERNAL:
  # - Domain services use many ports (DNS, Kerberos, LDAP, etc.)
  # - File sharing, printing, and other services
  # - Simpler than listing every port individually
  #
  # This is safe because it only allows traffic FROM our subnet
}

# Allow all internal traffic for Windows VMs
resource "openstack_networking_secgroup_rule_v2" "windows_internal_all" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = ""                # All protocols
  remote_ip_prefix  = var.subnet_cidr   # From our subnet only
  security_group_id = openstack_networking_secgroup_v2.windows_sg.id

  # COMMON WINDOWS PORTS (all covered by this rule):
  # - DNS: 53 (TCP/UDP)
  # - Kerberos: 88 (TCP/UDP)
  # - LDAP: 389 (TCP/UDP)
  # - SMB: 445 (TCP)
  # - Active Directory: 3268, 3269 (TCP)
}

# ==============================================================================
# UNDERSTANDING SECURITY GROUPS
# ==============================================================================
#
# EXAMPLE TRAFFIC FLOW:
#
# 1. You try to SSH to a Linux VM from the jump host
#    - Traffic arrives at VM on port 22
#    - Security group checks: Is there an ingress rule for TCP port 22?
#    - Yes! ssh_ingress rule allows it
#    - Connection succeeds
#
# 2. You try to connect to port 8080 on a Linux VM
#    - Traffic arrives at VM on port 8080
#    - Security group checks: Is there an ingress rule for TCP port 8080?
#    - No rule found
#    - Connection DENIED (times out)
#
# ==============================================================================
# ADDING RULES FOR YOUR COMPETITION
# ==============================================================================
#
# COMMON PORTS YOU MIGHT NEED:
#
# WEB SERVICES:
# resource "openstack_networking_secgroup_rule_v2" "http" {
#   direction         = "ingress"
#   ethertype         = "IPv4"
#   protocol          = "tcp"
#   port_range_min    = 80
#   port_range_max    = 80
#   remote_ip_prefix  = "0.0.0.0/0"
#   security_group_id = openstack_networking_secgroup_v2.linux_sg.id
# }
#
# resource "openstack_networking_secgroup_rule_v2" "https" {
#   direction         = "ingress"
#   ethertype         = "IPv4"
#   protocol          = "tcp"
#   port_range_min    = 443
#   port_range_max    = 443
#   remote_ip_prefix  = "0.0.0.0/0"
#   security_group_id = openstack_networking_secgroup_v2.linux_sg.id
# }
#
# DATABASE:
# resource "openstack_networking_secgroup_rule_v2" "mysql" {
#   direction         = "ingress"
#   ethertype         = "IPv4"
#   protocol          = "tcp"
#   port_range_min    = 3306
#   port_range_max    = 3306
#   remote_ip_prefix  = var.subnet_cidr  # Only internal access
#   security_group_id = openstack_networking_secgroup_v2.linux_sg.id
# }
#
# EMAIL:
# resource "openstack_networking_secgroup_rule_v2" "smtp" {
#   direction         = "ingress"
#   ethertype         = "IPv4"
#   protocol          = "tcp"
#   port_range_min    = 25
#   port_range_max    = 25
#   remote_ip_prefix  = "0.0.0.0/0"
#   security_group_id = openstack_networking_secgroup_v2.linux_sg.id
# }
#
# PORT RANGES (e.g., for FTP passive mode):
# resource "openstack_networking_secgroup_rule_v2" "ftp_passive" {
#   direction         = "ingress"
#   ethertype         = "IPv4"
#   protocol          = "tcp"
#   port_range_min    = 50000
#   port_range_max    = 50100
#   remote_ip_prefix  = "0.0.0.0/0"
#   security_group_id = openstack_networking_secgroup_v2.linux_sg.id
# }
#
# ==============================================================================
# SECURITY CONSIDERATIONS FOR COMPETITIONS
# ==============================================================================
#
# For a CCDC-style competition, you might want different security groups
# for different network segments:
#
# 1. DMZ Security Group (public-facing services)
#    - Allow HTTP (80), HTTPS (443), SMTP (25), DNS (53)
#    - Restrict SSH to management network only
#
# 2. Internal Security Group (internal services)
#    - Allow traffic only from DMZ and internal networks
#    - Block direct external access
#
# 3. Management Security Group (Grey Team only)
#    - Restrict to Grey Team IP ranges
#    - Allow all ports for administration
#
# 4. Red Team Security Group
#    - Initially restricted
#    - Red Team must "break in" through DMZ services
#
# ==============================================================================
