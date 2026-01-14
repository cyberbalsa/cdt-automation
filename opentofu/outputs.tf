# ==============================================================================
# OUTPUTS
# ==============================================================================
# Outputs display useful information after 'tofu apply' completes.
# They also make values available to other tools (like our Python script).
#
# HOW OUTPUTS WORK:
# - Defined here, displayed after apply
# - View anytime with: tofu output
# - Get JSON format with: tofu output -json
# - Access specific output: tofu output windows_vm_ips
#
# WHY OUTPUTS MATTER:
# - See IP addresses without opening the dashboard
# - Pass information to Ansible inventory script
# - Share values between Terraform/OpenTofu modules
#
# DOCUMENTATION:
# - OpenTofu Outputs: https://opentofu.org/docs/language/values/outputs/
# - Terraform Outputs: https://developer.hashicorp.com/terraform/language/values/outputs
#
# ==============================================================================

# ------------------------------------------------------------------------------
# WINDOWS VM OUTPUTS
# ------------------------------------------------------------------------------
# Information about Windows virtual machines.

output "windows_vm_ips" {
  description = "Floating (public) IP addresses for Windows VMs"
  value       = [for fip in openstack_networking_floatingip_v2.win_fip : fip.address]

  # FOR LOOP EXPLAINED:
  # [for ITEM in COLLECTION : EXPRESSION]
  #
  # This iterates over all floating IPs and extracts the address:
  # - win_fip is a list (because we used count)
  # - fip is each item in the list
  # - fip.address is the IP address string
  #
  # Result: ["100.65.4.51", "100.65.4.52", "100.65.4.53"]
  #
  # USE THIS IP TO:
  # - SSH through jump host: ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<ip>
  # - RDP through tunnel: ssh -L 3389:<ip>:3389 sshjump@ssh.cyberrange.rit.edu
}

output "windows_vm_names" {
  description = "Hostnames of Windows VMs"
  value       = [for vm in openstack_compute_instance_v2.windows : vm.name]

  # Result: ["dc01", "cdt-win-2", "cdt-win-3"]
  # (Names depend on windows_hostnames variable)
}

output "windows_vm_internal_ips" {
  description = "Internal (private) IP addresses for Windows VMs"
  value       = [for vm in openstack_compute_instance_v2.windows : vm.access_ip_v4]

  # Result: ["10.10.10.21", "10.10.10.22", "10.10.10.23"]
  #
  # INTERNAL vs FLOATING IPS:
  # - Internal IPs: Used for VM-to-VM communication on private network
  # - Floating IPs: Used for external access through jump host
  #
  # Domain services (DNS, AD) use internal IPs
  # You access VMs externally using floating IPs
}

# ------------------------------------------------------------------------------
# LINUX VM OUTPUTS
# ------------------------------------------------------------------------------
# Information about Linux virtual machines.

output "debian_vm_ips" {
  description = "Floating (public) IP addresses for Linux VMs"
  value       = [for fip in openstack_networking_floatingip_v2.debian_fip : fip.address]

  # Result: ["100.65.4.61", "100.65.4.62", "100.65.4.63", "100.65.4.64"]
}

output "debian_vm_names" {
  description = "Hostnames of Linux VMs"
  value       = [for vm in openstack_compute_instance_v2.debian : vm.name]

  # Result: ["webserver", "cdt-debian-2", "cdt-debian-3", "cdt-debian-4"]
}

output "debian_vm_internal_ips" {
  description = "Internal (private) IP addresses for Linux VMs"
  value       = [for vm in openstack_compute_instance_v2.debian : vm.access_ip_v4]

  # Result: ["10.10.10.31", "10.10.10.32", "10.10.10.33", "10.10.10.34"]
}

# ==============================================================================
# UNDERSTANDING OUTPUT VALUES
# ==============================================================================
#
# After running 'tofu apply', you'll see output like this:
#
#   Apply complete! Resources: 12 added, 0 changed, 0 destroyed.
#
#   Outputs:
#
#   debian_vm_internal_ips = [
#     "10.10.10.31",
#     "10.10.10.32",
#   ]
#   debian_vm_ips = [
#     "100.65.4.61",
#     "100.65.4.62",
#   ]
#   debian_vm_names = [
#     "webserver",
#     "cdt-debian-2",
#   ]
#   windows_vm_internal_ips = [
#     "10.10.10.21",
#     "10.10.10.22",
#   ]
#   windows_vm_ips = [
#     "100.65.4.51",
#     "100.65.4.52",
#   ]
#   windows_vm_names = [
#     "dc01",
#     "cdt-win-2",
#   ]
#
# ==============================================================================
# HOW THE INVENTORY SCRIPT USES OUTPUTS
# ==============================================================================
#
# The import-tofu-to-ansible.py script runs 'tofu output -json' to get
# this information in a machine-readable format:
#
#   {
#     "windows_vm_names": {"value": ["dc01", "cdt-win-2"]},
#     "windows_vm_ips": {"value": ["100.65.4.51", "100.65.4.52"]},
#     "windows_vm_internal_ips": {"value": ["10.10.10.21", "10.10.10.22"]},
#     ...
#   }
#
# The script parses this JSON and creates the Ansible inventory file with
# all the hostnames, IP addresses, and connection settings.
#
# ==============================================================================
# ADDING OUTPUTS FOR YOUR COMPETITION
# ==============================================================================
#
# When you add new VM types, add corresponding outputs:
#
# output "redteam_vm_ips" {
#   description = "Floating IPs for Red Team attack machines"
#   value       = [for fip in openstack_networking_floatingip_v2.redteam_fip : fip.address]
# }
#
# output "redteam_vm_names" {
#   description = "Hostnames of Red Team machines"
#   value       = [for vm in openstack_compute_instance_v2.redteam : vm.name]
# }
#
# output "redteam_vm_internal_ips" {
#   description = "Internal IPs for Red Team machines"
#   value       = [for vm in openstack_compute_instance_v2.redteam : vm.access_ip_v4]
# }
#
# THEN: Update import-tofu-to-ansible.py to read these new outputs
# and add them to the Ansible inventory.
#
# ==============================================================================
# OTHER USEFUL OUTPUTS
# ==============================================================================
#
# NETWORK INFORMATION:
# output "network_id" {
#   description = "ID of the private network"
#   value       = openstack_networking_network_v2.cdt_net.id
# }
#
# output "subnet_cidr" {
#   description = "CIDR of the private subnet"
#   value       = openstack_networking_subnet_v2.cdt_subnet.cidr
# }
#
# DOMAIN CONTROLLER INFO (for quick reference):
# output "domain_controller_ip" {
#   description = "Internal IP of the Domain Controller (first Windows VM)"
#   value       = openstack_compute_instance_v2.windows[0].access_ip_v4
# }
#
# output "domain_controller_floating_ip" {
#   description = "Floating IP of the Domain Controller"
#   value       = openstack_networking_floatingip_v2.win_fip[0].address
# }
#
# ==============================================================================
