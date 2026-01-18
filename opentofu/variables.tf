# ==============================================================================
# OPENTOFU VARIABLES
# ==============================================================================
# This file defines input variables that customize your infrastructure.
# Variables let you change settings without modifying the main code.
#
# DOCUMENTATION:
# - OpenTofu Variables: https://opentofu.org/docs/language/values/variables/
# - Terraform Variables (same syntax): https://developer.hashicorp.com/terraform/language/values/variables
#
# HOW VARIABLES WORK:
# 1. Each variable has a name, type, and default value
# 2. You can override defaults by:
#    - Creating a terraform.tfvars file
#    - Using -var flag: tofu apply -var="windows_count=5"
#    - Setting environment variables: TF_VAR_windows_count=5
#
# ==============================================================================

# ------------------------------------------------------------------------------
# NETWORK CONFIGURATION
# ------------------------------------------------------------------------------
# These variables define your private network settings.
# The network is where your VMs communicate with each other.

variable "network_name" {
  description = "Name for the private network (appears in OpenStack dashboard)"
  type        = string
  default     = "cdt-net"

  # TYPE EXPLANATION:
  # - string: Text value (must be in quotes)
  # - number: Numeric value (no quotes)
  # - bool: true or false
  # - list(string): A list of strings like ["a", "b", "c"]
  # - map(string): Key-value pairs like {key1 = "value1", key2 = "value2"}
}

variable "subnet_cidr" {
  description = "IP address range for the private network in CIDR notation"
  type        = string
  default     = "10.10.10.0/24"

  # CIDR NOTATION EXPLAINED:
  # - "10.10.10.0/24" means:
  #   - Network: 10.10.10.x
  #   - /24 = 256 addresses (10.10.10.0 to 10.10.10.255)
  #   - Usable IPs: 10.10.10.1 to 10.10.10.254 (first/last reserved)
  # - Common CIDR blocks:
  #   - /24 = 256 addresses (most common for small networks)
  #   - /16 = 65,536 addresses
  #   - /8 = 16,777,216 addresses
}

variable "router_name" {
  description = "Name for the router that connects your network to the internet"
  type        = string
  default     = "cdt-router"

  # ROUTER PURPOSE:
  # The router connects your private network (10.10.10.0/24) to the
  # external network (MAIN-NAT) so your VMs can reach the internet
  # and receive floating IPs for external access.
}

variable "external_network" {
  description = "Name of the external/public network in OpenStack (for internet access)"
  type        = string
  default     = "MAIN-NAT"

  # EXTERNAL NETWORK:
  # This is a pre-existing network in OpenStack that provides internet access.
  # At RIT CyberRange, this is "MAIN-NAT" with the 100.65.0.0/16 range.
  # You cannot create this - it's managed by OpenStack administrators.
}

# ------------------------------------------------------------------------------
# VM IMAGE CONFIGURATION
# ------------------------------------------------------------------------------
# These variables specify which operating system images to use.
# Images must exist in OpenStack before you can use them.

variable "windows_image_name" {
  description = "Name of the Windows image in OpenStack Glance"
  type        = string
  default     = "WindowsServer2022"

  # VIEW AVAILABLE IMAGES:
  # 1. OpenStack Dashboard: Compute → Images
  # 2. Command line: openstack image list
  #
  # Common images at RIT CyberRange:
  # - WindowsServer2022
  # - WindowsServer2019
  # - Windows10
}

variable "debian_image_name" {
  description = "Name of the Linux image in OpenStack Glance"
  type        = string
  default     = "Ubuntu2404Desktop"

  # NOTE: Despite the variable name saying "debian", you can use any Linux image.
  # The default uses Ubuntu with LXQT desktop pre-installed.
  #
  # Common Linux images:
  # - Ubuntu2404Desktop (Ubuntu 24.04 with LXQT)
  # - debian-trixie-amd64-cloud
  # - kali-2024 (for Red Team attack machines)
}

# ------------------------------------------------------------------------------
# VM SIZE CONFIGURATION
# ------------------------------------------------------------------------------

variable "flavor_name" {
  description = "OpenStack flavor (VM size) defining CPU, RAM, and disk"
  type        = string
  default     = "medium"

  # FLAVORS EXPLAINED:
  # A "flavor" defines the virtual hardware for your VM.
  # Common flavors at RIT CyberRange:
  #   - small:  1 vCPU, 2GB RAM
  #   - medium: 2 vCPU, 4GB RAM
  #   - large:  4 vCPU, 8GB RAM
  #
  # Check available flavors:
  # - Dashboard: Compute → Instances → Launch Instance → Flavor
  # - Command: openstack flavor list
  #
  # Windows Server needs at least "medium" (4GB RAM recommended)
}

# ------------------------------------------------------------------------------
# SSH KEY CONFIGURATION
# ------------------------------------------------------------------------------

variable "keypair" {
  description = "Name of the SSH keypair in OpenStack (must be uploaded first)"
  type        = string
  default     = "homefedora"

  # IMPORTANT: Change this to YOUR keypair name!
  #
  # SSH KEYPAIRS:
  # 1. Your keypair must be uploaded to OpenStack BEFORE running tofu apply
  # 2. Upload location: Dashboard → Compute → Key Pairs → Import Public Key
  # 3. Use the SAME name here that you used when uploading
  #
  # Windows requires RSA keys. If you have ed25519, create an RSA key:
  #   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_openstack
  #
  # DOCUMENTATION:
  # https://docs.openstack.org/horizon/latest/user/configure-access-and-security-for-instances.html
}

# ------------------------------------------------------------------------------
# VM COUNT CONFIGURATION
# ------------------------------------------------------------------------------
# These variables control how many VMs to create.

variable "windows_count" {
  description = "Number of Windows VMs to create"
  type        = number
  default     = 2

  # COUNT BEHAVIOR:
  # - The FIRST Windows VM becomes the Domain Controller
  # - Additional VMs become domain member servers
  # - IP addresses: 10.10.10.21, 10.10.10.22, 10.10.10.23, etc.
  #
  # For a basic competition, you need at least:
  # - 1 Domain Controller
  # - 1+ Member servers for Blue Team to defend
  # - Consider: 1 per Blue Team member, or shared servers
}

variable "debian_count" {
  description = "Number of Linux VMs to create"
  type        = number
  default     = 2

  # COUNT BEHAVIOR:
  # - All Linux VMs join the Windows domain
  # - IP addresses: 10.10.10.31, 10.10.10.32, 10.10.10.33, etc.
  #
  # For a competition, consider:
  # - Web servers, database servers, mail servers
  # - One VM per Blue Team member as workstations
  # - Ansible control node (run playbooks from inside the network)
}

# ------------------------------------------------------------------------------
# CUSTOM HOSTNAME CONFIGURATION
# ------------------------------------------------------------------------------
# These variables let you give meaningful names to your VMs.

variable "windows_hostnames" {
  description = "Custom hostnames for Windows VMs (optional)"
  type        = list(string)
  default     = ["dc01"]

  # LIST VARIABLE EXPLAINED:
  # - list(string) means a list of text values
  # - Syntax: ["first", "second", "third"]
  #
  # HOW IT WORKS:
  # - If you provide names, VMs use those names
  # - If the list is shorter than windows_count, remaining VMs get auto-names
  # - Auto-names follow pattern: cdt-win-1, cdt-win-2, etc.
  #
  # EXAMPLE:
  # windows_count = 3
  # windows_hostnames = ["dc01", "fileserver"]
  # Result: dc01, fileserver, cdt-win-3
  #
  # FOR YOUR COMPETITION:
  # Use descriptive names that match your scenario:
  # ["dc01", "exchange", "fileserver", "webserver"]
}

variable "debian_hostnames" {
  description = "Custom hostnames for Linux VMs (optional)"
  type        = list(string)
  default     = ["webserver"]

  # EXAMPLE FOR COMPETITION:
  # debian_hostnames = ["web01", "db01", "mail01", "jumphost", "ansible"]
  #
  # NAMING CONVENTIONS:
  # - Use lowercase (Linux is case-sensitive)
  # - Avoid spaces and special characters
  # - Keep names short but descriptive
  # - Consider including the role: web01, db01, app01
}

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

# ==============================================================================
# ADDING NEW VARIABLES
# ==============================================================================
# To add a variable for your competition:
#
# 1. Define it here:
#    variable "my_variable" {
#      description = "What this variable does"
#      type        = string
#      default     = "default_value"
#    }
#
# 2. Use it in other .tf files:
#    name = var.my_variable
#
# 3. Override the default (optional):
#    - In terraform.tfvars: my_variable = "new_value"
#    - On command line: tofu apply -var="my_variable=new_value"
#
# DOCUMENTATION:
# - Variable Types: https://opentofu.org/docs/language/expressions/types/
# - Variable Validation: https://opentofu.org/docs/language/values/variables/#custom-validation-rules
# ==============================================================================
