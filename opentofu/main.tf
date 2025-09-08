terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 1.52.1"
    }
  }
}

# READ THIS: https://search.opentofu.org/provider/terraform-provider-openstack/openstack/latest
provider "openstack" {
  auth_url                        = "https://openstack.cyberrange.rit.edu:5000/v3"
  region                         = "CyberRange"
  tenant_name                    = "cdtadmin"
  application_credential_id      = "27d63cf4e0a043e9a7b8b1a550385e51"
  application_credential_secret  = "HFN6hDUB6rnBIYKD1J8m31KgGzGKrFOdqwJfvVka8rcFlO42qXz8XetKTtm_qKqwJDnlWYYnFJbyw-X-X_5JMA"
}
