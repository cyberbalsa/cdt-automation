resource "openstack_compute_instance_v2" "windows" {
  count       = var.windows_count
  name        = "cdt-win-${count.index + 1}"
  image_name  = var.windows_image_name
  flavor_name = var.flavor_name
  key_pair    = var.keypair

  network {
    uuid = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.2${count.index + 1}"
  }

  user_data = file("${path.module}/windows-userdata.ps1")

  depends_on = [
  ]
}

resource "openstack_compute_instance_v2" "debian" {
  count       = var.debian_count
  name        = "cdt-debian-${count.index + 1}"
  image_name  = var.debian_image_name
  flavor_name = var.flavor_name
  key_pair    = var.keypair

  network {
    uuid = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.3${count.index + 1}"
  }

  user_data = file("${path.module}/debian-userdata.yaml")

  depends_on = [
  ]
}


resource "openstack_networking_floatingip_v2" "win_fip" {
  count = var.windows_count
  pool  = var.external_network
}

resource "openstack_networking_floatingip_v2" "debian_fip" {
  count = var.debian_count
  pool  = var.external_network
}

# Data sources to get the port IDs for the instances
data "openstack_networking_port_v2" "win_port" {
  count      = var.windows_count
  device_id  = openstack_compute_instance_v2.windows[count.index].id
  network_id = openstack_networking_network_v2.cdt_net.id
}

data "openstack_networking_port_v2" "debian_port" {
  count      = var.debian_count
  device_id  = openstack_compute_instance_v2.debian[count.index].id
  network_id = openstack_networking_network_v2.cdt_net.id
}

resource "openstack_networking_floatingip_associate_v2" "win_fip_assoc" {
  count       = var.windows_count
  floating_ip = openstack_networking_floatingip_v2.win_fip[count.index].address
  port_id     = data.openstack_networking_port_v2.win_port[count.index].id
}

resource "openstack_networking_floatingip_associate_v2" "debian_fip_assoc" {
  count       = var.debian_count
  floating_ip = openstack_networking_floatingip_v2.debian_fip[count.index].address
  port_id     = data.openstack_networking_port_v2.debian_port[count.index].id
}
