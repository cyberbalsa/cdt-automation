# ==============================================================================
# NETWORK CONFIGURATION
# ==============================================================================
# This file creates the virtual network infrastructure in OpenStack.
# Think of it like setting up the cables and switches for your servers.
#
# WHAT GETS CREATED:
# 1. A private network (like your office LAN)
# 2. A subnet (the IP address range for that network)
# 3. A router (connects your private network to the internet)
#
# DOCUMENTATION:
# - Network Resource: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_network_v2
# - Subnet Resource: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_subnet_v2
# - Router Resource: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_router_v2
#
# ==============================================================================

# ------------------------------------------------------------------------------
# PRIVATE NETWORK
# ------------------------------------------------------------------------------
# Creates a virtual network that your VMs will connect to.
# This is like creating a virtual ethernet switch.
#
# RESOURCE SYNTAX EXPLAINED:
#   resource "TYPE" "NAME" { ... }
#   - TYPE: The kind of resource (openstack_networking_network_v2)
#   - NAME: Your identifier to reference this resource elsewhere (cdt_net)
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_network_v2

resource "openstack_networking_network_v2" "cdt_net" {
  provider = openstack.main
  # PROVIDER EXPLAINED:
  # In a multi-project setup (like a CTF with separate Blue/Red teams),
  # we need to specify WHICH OpenStack project owns each resource.
  # "openstack.main" refers to the provider alias defined in main.tf
  # This network lives in the main/scoring project and is shared with others.

  name = var.network_name
  # var.network_name references the variable defined in variables.tf
  # This lets you change the name without editing this file

  # OPTIONAL ATTRIBUTES (not used here but available):
  # admin_state_up = true          # Enable/disable the network
  # shared = false                 # Share network with other projects
  # description = "My network"     # Human-readable description
}

# ------------------------------------------------------------------------------
# SUBNET
# ------------------------------------------------------------------------------
# Defines the IP address range for your network.
# VMs on this network will get IP addresses from this range.
#
# HOW SUBNETS WORK:
# - CIDR "10.10.10.0/24" provides 256 addresses
# - Gateway (10.10.10.1) is the router's address on this network
# - DHCP can automatically assign IPs, or you can set fixed IPs
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_subnet_v2

resource "openstack_networking_subnet_v2" "cdt_subnet" {
  provider = openstack.main
  # Subnet must be in the same project as its parent network

  name       = "${var.network_name}-subnet"
  # ${...} is string interpolation - inserts variable value into string
  # Result: "cdt-net-subnet"

  network_id = openstack_networking_network_v2.cdt_net.id
  # References the network created above
  # Syntax: RESOURCE_TYPE.RESOURCE_NAME.ATTRIBUTE
  # .id returns the unique identifier OpenStack assigned to the network

  cidr       = var.subnet_cidr
  # The IP range: "10.10.10.0/24"
  # VMs will get addresses like 10.10.10.21, 10.10.10.31, etc.

  ip_version = 4
  # IPv4 (most common) or 6 for IPv6

  dns_nameservers = ["129.21.3.17", "129.21.4.18"]
  # DNS servers for name resolution (these are RIT's DNS servers)
  # VMs use these to resolve domain names like google.com
  # After domain setup, you might change this to point to your DC

  # OPTIONAL ATTRIBUTES (not used here):
  # gateway_ip = "10.10.10.1"      # Router's IP (auto-assigned if not set)
  # enable_dhcp = true             # Auto-assign IPs to VMs
  # allocation_pools = [...]       # Limit which IPs DHCP can assign
}

# ------------------------------------------------------------------------------
# ROUTER
# ------------------------------------------------------------------------------
# Connects your private network to the external network (internet).
# Without a router, your VMs cannot reach the internet or receive floating IPs.
#
# HOW ROUTING WORKS:
# 1. VMs on private network (10.10.10.x) send traffic to the router
# 2. Router forwards traffic to the external network (MAIN-NAT)
# 3. External network provides internet access
# 4. Floating IPs allow inbound connections from outside
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_router_v2

resource "openstack_networking_router_v2" "cdt_router" {
  provider = openstack.main
  # Router lives in the main project, provides internet for all teams

  name                = var.router_name
  external_network_id = data.openstack_networking_network_v2.ext_net.id
  # Points to the external network for internet access
  # Uses a "data" source (see below) to look up the existing network

  # OPTIONAL ATTRIBUTES:
  # admin_state_up = true          # Enable/disable router
  # enable_snat = true             # Source NAT for outbound traffic
  # description = "Main router"    # Human-readable description
}

# ------------------------------------------------------------------------------
# ROUTER INTERFACE
# ------------------------------------------------------------------------------
# Attaches the router to your subnet.
# This creates the connection between your private network and the router.
#
# Think of it like plugging a cable from your switch into the router.
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_router_interface_v2

resource "openstack_networking_router_interface_v2" "cdt_router_interface" {
  provider = openstack.main
  # Interface connects router to subnet, both in main project

  router_id = openstack_networking_router_v2.cdt_router.id
  subnet_id = openstack_networking_subnet_v2.cdt_subnet.id

  # After this is created, traffic from VMs on cdt_subnet can reach
  # the router, and from there, the internet.
}

# ------------------------------------------------------------------------------
# DATA SOURCE: EXTERNAL NETWORK
# ------------------------------------------------------------------------------
# Looks up an EXISTING network in OpenStack (doesn't create anything).
# We need this to find the external network's ID for the router.
#
# DATA SOURCE vs RESOURCE:
# - "resource" creates something new
# - "data" looks up something that already exists
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/networking_network_v2

data "openstack_networking_network_v2" "ext_net" {
  name = var.external_network
  # Looks up the network named "MAIN-NAT"
  # This network is managed by OpenStack admins, we just reference it
}

# ==============================================================================
# NETWORK TOPOLOGY SUMMARY
# ==============================================================================
#
#                    INTERNET
#                        |
#                   [MAIN-NAT]     <- External network (100.65.0.0/16)
#                        |
#                  [cdt_router]    <- Your router
#                        |
#                  [cdt_subnet]    <- Your subnet (10.10.10.0/24)
#                        |
#           +------------+------------+
#           |            |            |
#        [VM 1]       [VM 2]       [VM 3]
#      10.10.10.21  10.10.10.22  10.10.10.31
#
# Each VM also gets a "floating IP" from MAIN-NAT (like 100.65.4.55)
# which allows external access through the jump host.
#
# ==============================================================================
# RBAC POLICIES - SHARE NETWORK WITH BLUE AND RED TEAMS
# ==============================================================================
# WHAT IS RBAC (Role-Based Access Control)?
# In OpenStack, each "project" (tenant) is isolated by default. Resources in
# one project can't see or use resources in another project. This is great
# for security but problematic for a CTF where we want:
#
#   - Main project: Owns the network, runs scoring infrastructure
#   - Blue project: Blue team VMs that defenders manage
#   - Red project: Red team attack VMs
#
# All these VMs need to be on the SAME network so they can communicate,
# but they live in different projects for access control and quota management.
#
# RBAC policies solve this by explicitly granting access to specific resources
# across project boundaries. We share the network (not the VMs) so all teams'
# VMs can attach to it.
#
# WHY USE SEPARATE PROJECTS FOR A CTF?
# 1. Quota isolation: Red team can't accidentally (or intentionally) consume
#    all resources meant for Blue team
# 2. Access control: Blue team can't see Red team's VMs in the dashboard
# 3. Billing/tracking: Easy to see resource usage per team
# 4. Realistic simulation: Mirrors real-world multi-tenant environments
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_rbac_policy_v2
# OpenStack docs: https://docs.openstack.org/neutron/latest/admin/config-rbac.html

resource "openstack_networking_rbac_policy_v2" "share_with_blue" {
  provider = openstack.main
  # RBAC policy is created in the project that OWNS the network (main)

  action = "access_as_shared"
  # "access_as_shared" allows the target project to use this network
  # VMs in the Blue project can now attach to this network

  object_id   = openstack_networking_network_v2.cdt_net.id
  object_type = "network"
  # What we're sharing: the cdt_net network

  target_tenant = var.blue_project_id
  # WHO we're sharing with: the Blue Team project
  # "tenant" is the old OpenStack term for "project"
}

resource "openstack_networking_rbac_policy_v2" "share_with_red" {
  provider = openstack.main

  action      = "access_as_shared"
  object_id   = openstack_networking_network_v2.cdt_net.id
  object_type = "network"

  target_tenant = var.red_project_id
  # Share with Red Team - their Kali VMs can now attack Blue Team VMs
  # on the same network, just like in a real attack scenario!
}

# ==============================================================================
# CTF NETWORK ARCHITECTURE
# ==============================================================================
#
#                         INTERNET
#                             |
#                        [MAIN-NAT]
#                             |
#                       [cdt_router]
#                             |
#           +-----------------+-----------------+
#           |                 |                 |
#      MAIN PROJECT     BLUE PROJECT      RED PROJECT
#      (owns network)   (shared access)   (shared access)
#           |                 |                 |
#      [Scoring VM]     [Windows DC]      [Kali VM 1]
#      10.10.10.11      10.10.10.21       10.10.10.41
#                       [Windows VM]      [Kali VM 2]
#                       10.10.10.22       10.10.10.42
#                       [Linux VM]
#                       10.10.10.31
#
# All VMs share the same 10.10.10.0/24 network via RBAC sharing.
# Red can attack Blue. Scoring can monitor both. Nobody can see each
# other's VMs in the OpenStack dashboard - only network traffic.
#
# ==============================================================================

# ==============================================================================
# ADDING MORE NETWORKS FOR YOUR COMPETITION
# ==============================================================================
# For a CCDC-style competition, you might want multiple network segments:
#
# EXAMPLE: Adding a DMZ network for public-facing services
#
# resource "openstack_networking_network_v2" "dmz_net" {
#   provider = openstack.main
#   name     = "competition-dmz"
# }
#
# resource "openstack_networking_subnet_v2" "dmz_subnet" {
#   provider   = openstack.main
#   name       = "dmz-subnet"
#   network_id = openstack_networking_network_v2.dmz_net.id
#   cidr       = "192.168.10.0/24"
#   ip_version = 4
# }
#
# resource "openstack_networking_router_interface_v2" "dmz_interface" {
#   provider  = openstack.main
#   router_id = openstack_networking_router_v2.cdt_router.id
#   subnet_id = openstack_networking_subnet_v2.dmz_subnet.id
# }
#
# # Don't forget to share the new network with Blue/Red!
# resource "openstack_networking_rbac_policy_v2" "dmz_share_blue" {
#   provider      = openstack.main
#   action        = "access_as_shared"
#   object_id     = openstack_networking_network_v2.dmz_net.id
#   object_type   = "network"
#   target_tenant = var.blue_project_id
# }
#
# Then update instances.tf to put web servers on the DMZ network.
# ==============================================================================
