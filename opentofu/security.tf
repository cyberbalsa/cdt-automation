# Security group for Linux VMs (SSH access)
resource "openstack_networking_secgroup_v2" "linux_sg" {
  name        = "cdt-linux-sg"
  description = "Security group for Linux VMs with SSH access"
}

# Security group for Windows VMs (WinRM access)
resource "openstack_networking_secgroup_v2" "windows_sg" {
  name        = "cdt-windows-sg"
  description = "Security group for Windows VMs with WinRM access"
}

# Allow SSH (port 22) from anywhere for Linux VMs
resource "openstack_networking_secgroup_rule_v2" "ssh_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.linux_sg.id
}

# Allow RDP (port 3389) from anywhere for Linux VMs (xrdp)
resource "openstack_networking_secgroup_rule_v2" "linux_rdp_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.linux_sg.id
}

# Allow WinRM HTTP (port 5985) from anywhere for Windows VMs
resource "openstack_networking_secgroup_rule_v2" "winrm_http_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5985
  port_range_max    = 5985
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.windows_sg.id
}

# Allow WinRM HTTPS (port 5986) from anywhere for Windows VMs
resource "openstack_networking_secgroup_rule_v2" "winrm_https_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5986
  port_range_max    = 5986
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.windows_sg.id
}

# Allow RDP (port 3389) from anywhere for Windows VMs (commonly needed)
resource "openstack_networking_secgroup_rule_v2" "rdp_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.windows_sg.id
}

# Allow all traffic between VMs on the network for Linux VMs
resource "openstack_networking_secgroup_rule_v2" "linux_internal_all" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = ""
  remote_ip_prefix  = var.subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.linux_sg.id
}

# Allow all traffic between VMs on the network for Windows VMs
resource "openstack_networking_secgroup_rule_v2" "windows_internal_all" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = ""
  remote_ip_prefix  = var.subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.windows_sg.id
}
