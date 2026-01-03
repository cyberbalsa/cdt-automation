# OpenTofu variables for OpenStack project
variable "network_name" {
  type    = string
  default = "cdt-net"
}

variable "subnet_cidr" {
  type    = string
  default = "10.10.10.0/24"
}

variable "router_name" {
  type    = string
  default = "cdt-router"
}

variable "windows_image_name" {
  type    = string
  default = "WindowsServer2022"
}

variable "debian_image_name" {
  type    = string
  default = "Ubuntu2404Desktop"
}

variable "flavor_name" {
  type    = string
  default = "medium"
}

variable "keypair" {
  type    = string
  default = "coredesktop"
}

variable "external_network" {
  type    = string
  default = "MAIN-NAT"
}

variable "windows_count" {
  type    = number
  default = 3
}

variable "debian_count" {
  type    = number
  default = 4
}

variable "windows_hostnames" {
  type        = list(string)
  default     = ["dc01"]
  description = "Optional custom hostnames for Windows VMs. If empty or shorter than windows_count, auto-generated names will be used."
}

variable "debian_hostnames" {
  type        = list(string)
  default     = ["webserver"]
  description = "Optional custom hostnames for Debian VMs. If empty or shorter than debian_count, auto-generated names will be used."
}
