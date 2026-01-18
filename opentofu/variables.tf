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

variable "scoring_image_name" {
  description = "Name of the image for scoring servers"
  type        = string
  default     = "Ubuntu2404Desktop"
}

variable "kali_image_name" {
  description = "Name of the Kali Linux image for Red Team"
  type        = string
  default     = "Kali2025"
  # Run 'openstack image list' to see available images
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

variable "scoring_count" {
  description = "Number of scoring servers to create in main project"
  type        = number
  default     = 1
}

variable "blue_windows_count" {
  description = "Number of Blue Team Windows VMs (first becomes Domain Controller)"
  type        = number
  default     = 2
}

variable "blue_linux_count" {
  description = "Number of Blue Team Linux VMs"
  type        = number
  default     = 2
}

variable "red_kali_count" {
  description = "Number of Red Team Kali attack VMs"
  type        = number
  default     = 2
}

# ------------------------------------------------------------------------------
# CUSTOM HOSTNAME CONFIGURATION
# ------------------------------------------------------------------------------
# These variables let you give meaningful names to your VMs.

variable "blue_windows_hostnames" {
  description = "Custom hostnames for Blue Team Windows VMs (optional)"
  type        = list(string)
  default     = ["dc01"]
}

variable "blue_linux_hostnames" {
  description = "Custom hostnames for Blue Team Linux VMs (optional)"
  type        = list(string)
  default     = ["webserver"]
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
