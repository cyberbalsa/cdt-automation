terraform {
  required_version = ">= 1.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 1.52.1"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0"
    }
  }
}

# READ THIS: https://search.opentofu.org/provider/terraform-provider-openstack/openstack/latest
# IMPORTANT: Credentials are loaded from environment variables
#
# Setup instructions:
# 1. Download your OpenStack credentials file from the dashboard:
#    Identity → Application Credentials → Download openrc file
# 2. Move the file to the project root and run quick-start.sh
# 3. Before running tofu commands, always source the credentials:
#    source ../app-cred-openrc.sh
#
# The provider automatically reads these environment variables:
# - OS_APPLICATION_CREDENTIAL_ID
# - OS_APPLICATION_CREDENTIAL_SECRET
# - OS_REGION_NAME (optional)
provider "openstack" {
  auth_url = "https://openstack.cyberrange.rit.edu:5000/v3"
  region   = "CyberRange"

  # Credentials (ID and Secret) are automatically loaded from environment variables
  # set by sourcing app-cred-openrc.sh
}

# Validate that OpenStack credentials are loaded
# This will fail with a clear error message if you forget to source the credentials
# tflint-ignore: terraform_unused_declarations
data "external" "check_credentials" {
  program = ["bash", "-c", <<-EOT
    # Check if environment variables are set
    if [ -z "$OS_APPLICATION_CREDENTIAL_ID" ] || [ -z "$OS_APPLICATION_CREDENTIAL_SECRET" ]; then
      echo "" >&2
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
      echo "❌ ERROR: OpenStack credentials not loaded!" >&2
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
      echo "" >&2
      echo "You must source the credentials file before running tofu commands:" >&2
      echo "" >&2
      echo "    source ../app-cred-openrc.sh" >&2
      echo "" >&2
      echo "Then try running your tofu command again." >&2
      echo "" >&2
      echo "If you don't have the credentials file yet:" >&2
      echo "  1. Go to: https://openstack.cyberrange.rit.edu" >&2
      echo "  2. Navigate to: Identity → Application Credentials" >&2
      echo "  3. Create a new credential and download the openrc file" >&2
      echo "  4. Move it to the project root and run: ./quick-start.sh" >&2
      echo "" >&2
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
      exit 1
    fi

    # Return valid JSON if credentials are set
    echo '{"status":"ok"}'
  EOT
  ]
}

