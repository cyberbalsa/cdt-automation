# OpenTofu variables for OpenStack project
variable "network_name" { default = "cdt-net" }
variable "subnet_cidr" { default = "10.10.10.0/24" }
variable "router_name" { default = "cdt-router" }
variable "windows_image_name" { default = "WindowsServer2022" }
variable "debian_image_name" { default = "Ubuntu2404Desktop" }
variable "flavor_name" { default = "medium" }
variable "keypair" { default = "coredesktop" }
variable "security_group" { default = "main-boxes" }
variable "external_network" { default = "MAIN-NAT" }
variable "windows_count" { default = 3 }
variable "debian_count" { default = 4 }
