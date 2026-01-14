# ==============================================================================
# COMPUTE INSTANCES (VIRTUAL MACHINES)
# ==============================================================================
# This file creates the virtual machines in OpenStack.
# It also assigns floating IPs so you can access them from outside.
#
# WHAT GETS CREATED:
# 1. Windows VMs (for Domain Controller and member servers)
# 2. Linux VMs (for web servers, databases, workstations, etc.)
# 3. Floating IPs for each VM (public IP addresses)
# 4. Associations linking floating IPs to VMs
#
# DOCUMENTATION:
# - Compute Instance: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_instance_v2
# - Floating IP: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_floatingip_v2
# - Images Data Source: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/images_image_v2
#
# ==============================================================================

# ------------------------------------------------------------------------------
# DATA SOURCES: LOOK UP OS IMAGES
# ------------------------------------------------------------------------------
# These data sources find the image IDs for Windows and Linux.
# We need the image ID to create VMs from that image.
#
# DATA SOURCE EXPLAINED:
# - Queries OpenStack to find existing resources
# - Does NOT create anything
# - Returns information we can use elsewhere
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/images_image_v2

data "openstack_images_image_v2" "windows" {
  name        = var.windows_image_name    # "WindowsServer2022"
  most_recent = true                       # If multiple versions, use newest
  # Returns: data.openstack_images_image_v2.windows.id
}

data "openstack_images_image_v2" "debian" {
  name        = var.debian_image_name     # "Ubuntu2404Desktop"
  most_recent = true
  # Returns: data.openstack_images_image_v2.debian.id
}

# ==============================================================================
# WINDOWS VIRTUAL MACHINES
# ==============================================================================
# Creates Windows Server VMs for your domain infrastructure.
# The FIRST Windows VM becomes the Domain Controller (in Ansible).
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_instance_v2

resource "openstack_compute_instance_v2" "windows" {
  # --------------------------------------------------------------------------
  # COUNT - CREATE MULTIPLE VMS
  # --------------------------------------------------------------------------
  count = var.windows_count
  # count = 3 creates 3 identical VMs
  # Each VM is accessed via: openstack_compute_instance_v2.windows[0], [1], [2]
  # count.index gives the current index (0, 1, 2)

  # --------------------------------------------------------------------------
  # VM NAME - CONDITIONAL LOGIC
  # --------------------------------------------------------------------------
  name = length(var.windows_hostnames) > count.index ? var.windows_hostnames[count.index] : "cdt-win-${count.index + 1}"
  # This is a conditional expression (ternary operator):
  #   condition ? value_if_true : value_if_false
  #
  # EXPLAINED:
  # - length(var.windows_hostnames) = how many custom names provided
  # - count.index = current VM index (0, 1, 2, ...)
  # - If custom name exists for this index, use it
  # - Otherwise, generate name like "cdt-win-1", "cdt-win-2"
  #
  # EXAMPLE:
  #   windows_count = 3, windows_hostnames = ["dc01", "fileserver"]
  #   VM 0: "dc01" (custom)
  #   VM 1: "fileserver" (custom)
  #   VM 2: "cdt-win-3" (auto-generated)

  # --------------------------------------------------------------------------
  # VM CONFIGURATION
  # --------------------------------------------------------------------------
  image_name  = var.windows_image_name
  # The OS image to boot from (Windows Server 2022)

  flavor_name = var.flavor_name
  # VM size (CPU, RAM) - "medium" = 2 vCPU, 4GB RAM

  key_pair    = var.keypair
  # SSH key for initial access (also used by cloud-init on Windows)
  # IMPORTANT: Must match a keypair you uploaded to OpenStack

  security_groups = [openstack_networking_secgroup_v2.windows_sg.name]
  # Firewall rules applied to this VM
  # windows_sg allows WinRM (5985/5986) and RDP (3389)

  # --------------------------------------------------------------------------
  # NETWORK CONFIGURATION
  # --------------------------------------------------------------------------
  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    # Connect to our private network

    fixed_ip_v4 = "10.10.10.2${count.index + 1}"
    # Assign a specific IP address
    # String interpolation: "10.10.10.2" + (index + 1)
    # Results: 10.10.10.21, 10.10.10.22, 10.10.10.23, etc.
    #
    # WHY FIXED IPS:
    # - Predictable addressing for Ansible inventory
    # - Easy to remember which IP is which server
    # - Required for domain join and DNS configuration
  }

  # --------------------------------------------------------------------------
  # BOOT VOLUME (DISK)
  # --------------------------------------------------------------------------
  block_device {
    uuid                  = data.openstack_images_image_v2.windows.id
    # The Windows image to use

    source_type           = "image"
    # Boot from an image (vs. existing volume or snapshot)

    volume_size           = 80
    # Disk size in GB (Windows needs at least 40GB, 80GB recommended)

    destination_type      = "volume"
    # Create a Cinder volume (persistent storage)
    # Alternative: "local" for ephemeral storage (lost if VM deleted)

    delete_on_termination = true
    # Delete the volume when VM is destroyed
    # Set to false if you want to keep the disk after destroying VM
  }

  # --------------------------------------------------------------------------
  # USER DATA (CLOUD-INIT SCRIPT)
  # --------------------------------------------------------------------------
  user_data = file("${path.module}/windows-userdata.ps1")
  # Script that runs on first boot
  # For Windows: PowerShell script that enables WinRM for Ansible
  #
  # file() function reads the file contents
  # ${path.module} = directory containing this .tf file
  #
  # WHAT THE SCRIPT DOES:
  # 1. Enables WinRM (Windows Remote Management)
  # 2. Configures firewall for WinRM
  # 3. Sets up authentication for Ansible

  # --------------------------------------------------------------------------
  # DEPENDENCIES
  # --------------------------------------------------------------------------
  depends_on = [
    # List resources that must exist before creating this VM
    # Currently empty - OpenTofu figures out dependencies automatically
    # Add explicit dependencies if you have ordering requirements
  ]
}

# ==============================================================================
# LINUX VIRTUAL MACHINES
# ==============================================================================
# Creates Linux VMs for web servers, databases, workstations, etc.
# These will join the Windows domain via Ansible.
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_instance_v2

resource "openstack_compute_instance_v2" "debian" {
  count = var.debian_count

  # Hostname with same conditional logic as Windows
  name = length(var.debian_hostnames) > count.index ? var.debian_hostnames[count.index] : "cdt-debian-${count.index + 1}"

  image_name      = var.debian_image_name
  flavor_name     = var.flavor_name
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.linux_sg.name]
  # linux_sg allows SSH (22) and RDP (3389 for xRDP)

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = "10.10.10.3${count.index + 1}"
    # Linux IPs: 10.10.10.31, 10.10.10.32, 10.10.10.33, etc.
    # Different range than Windows (10.10.10.2x) for easy identification
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.debian.id
    source_type           = "image"
    volume_size           = 80
    destination_type      = "volume"
    delete_on_termination = true
  }

  user_data = file("${path.module}/debian-userdata.yaml")
  # Cloud-init YAML file for Linux
  # Sets up the cyberrange user with password authentication
  # Format: cloud-config YAML (different from Windows PowerShell)

  depends_on = []
}

# ==============================================================================
# FLOATING IPS
# ==============================================================================
# Floating IPs are public IP addresses that let you access VMs from outside.
# They come from the external network (MAIN-NAT) pool.
#
# HOW FLOATING IPS WORK:
# 1. OpenStack allocates an IP from the external pool (100.65.x.x)
# 2. You associate that IP with a VM's port
# 3. Traffic to the floating IP gets routed to your VM
# 4. You access the VM through the jump host using this IP
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_floatingip_v2

resource "openstack_networking_floatingip_v2" "win_fip" {
  count = var.windows_count
  pool  = var.external_network    # "MAIN-NAT"
  # Creates one floating IP per Windows VM
  # Access via: openstack_networking_floatingip_v2.win_fip[0].address
}

resource "openstack_networking_floatingip_v2" "debian_fip" {
  count = var.debian_count
  pool  = var.external_network
  # Creates one floating IP per Linux VM
}

# ==============================================================================
# DATA SOURCES: VM NETWORK PORTS
# ==============================================================================
# To associate a floating IP with a VM, we need the VM's network port ID.
# A "port" is the VM's connection point to the network.
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/networking_port_v2

data "openstack_networking_port_v2" "win_port" {
  count      = var.windows_count
  device_id  = openstack_compute_instance_v2.windows[count.index].id
  # Find the port belonging to this specific VM

  network_id = openstack_networking_network_v2.cdt_net.id
  # On this specific network
}

data "openstack_networking_port_v2" "debian_port" {
  count      = var.debian_count
  device_id  = openstack_compute_instance_v2.debian[count.index].id
  network_id = openstack_networking_network_v2.cdt_net.id
}

# ==============================================================================
# FLOATING IP ASSOCIATIONS
# ==============================================================================
# Links each floating IP to its VM's network port.
# After this, traffic to the floating IP reaches the VM.
#
# Documentation: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_floatingip_associate_v2

resource "openstack_networking_floatingip_associate_v2" "win_fip_assoc" {
  count       = var.windows_count
  floating_ip = openstack_networking_floatingip_v2.win_fip[count.index].address
  # The public IP address (e.g., 100.65.4.55)

  port_id     = data.openstack_networking_port_v2.win_port[count.index].id
  # The VM's network port to attach it to
}

resource "openstack_networking_floatingip_associate_v2" "debian_fip_assoc" {
  count       = var.debian_count
  floating_ip = openstack_networking_floatingip_v2.debian_fip[count.index].address
  port_id     = data.openstack_networking_port_v2.debian_port[count.index].id
}

# ==============================================================================
# UNDERSTANDING COUNT AND INDEXING
# ==============================================================================
#
# When you use count, OpenTofu creates a list of resources:
#
#   count = 3 creates:
#   - openstack_compute_instance_v2.windows[0]
#   - openstack_compute_instance_v2.windows[1]
#   - openstack_compute_instance_v2.windows[2]
#
# Inside the resource, count.index gives the current position:
#   - First VM: count.index = 0
#   - Second VM: count.index = 1
#   - Third VM: count.index = 2
#
# To reference a specific instance elsewhere:
#   openstack_compute_instance_v2.windows[0].id      # First VM's ID
#   openstack_compute_instance_v2.windows[*].id     # All VM IDs (splat)
#
# ==============================================================================
# ADDING NEW VM TYPES FOR YOUR COMPETITION
# ==============================================================================
#
# EXAMPLE: Adding Kali Linux attack machines for Red Team
#
# data "openstack_images_image_v2" "kali" {
#   name        = "kali-2024"
#   most_recent = true
# }
#
# resource "openstack_compute_instance_v2" "redteam" {
#   count           = var.redteam_count
#   name            = "red-attack-${count.index + 1}"
#   image_name      = "kali-2024"
#   flavor_name     = var.flavor_name
#   key_pair        = var.keypair
#   security_groups = [openstack_networking_secgroup_v2.linux_sg.name]
#
#   network {
#     uuid        = openstack_networking_network_v2.redteam_net.id
#     fixed_ip_v4 = "192.168.100.${count.index + 101}"
#   }
#
#   block_device {
#     uuid                  = data.openstack_images_image_v2.kali.id
#     source_type           = "image"
#     volume_size           = 80
#     destination_type      = "volume"
#     delete_on_termination = true
#   }
# }
#
# Don't forget:
# 1. Add redteam_count variable to variables.tf
# 2. Add redteam_net network to network.tf
# 3. Add floating IPs and associations
# 4. Add outputs to outputs.tf
# 5. Update import-tofu-to-ansible.py to include new VMs
#
# ==============================================================================
