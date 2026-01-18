# ==============================================================================
# MAIN CONFIGURATION - OpenTofu/Terraform Entry Point
# ==============================================================================
#
# WELCOME TO INFRASTRUCTURE AS CODE (IaC)!
# =========================================
# This project uses OpenTofu (an open-source fork of Terraform) to deploy
# a complete Attack/Defend CTF environment on OpenStack. Instead of clicking
# through web interfaces, we define our infrastructure in code files.
#
# WHY INFRASTRUCTURE AS CODE?
# - Reproducible: Deploy the same environment every time
# - Version controlled: Track changes with Git
# - Reviewable: Team members can review infrastructure changes
# - Automatable: CI/CD pipelines can deploy infrastructure
# - Documentable: The code IS the documentation
#
# FILE ORGANIZATION:
# ==================
# This project is split into multiple .tf files for clarity:
#
#   main.tf       <- YOU ARE HERE (providers, authentication)
#   variables.tf  <- Input variables you can customize
#   network.tf    <- Virtual networks, subnets, routers
#   security.tf   <- Firewall rules (security groups)
#   instances.tf  <- Virtual machines (compute instances)
#   outputs.tf    <- Information displayed after deployment
#
# OpenTofu reads ALL .tf files in a directory together - the split is just
# for human organization. You could put everything in one file, but don't!
#
# CTF ARCHITECTURE OVERVIEW:
# ==========================
# This deploys a multi-team Attack/Defend CTF environment:
#
#   +------------------+     +------------------+     +------------------+
#   |   MAIN PROJECT   |     |   BLUE PROJECT   |     |   RED PROJECT    |
#   |   (Grey Team)    |     |   (Defenders)    |     |   (Attackers)    |
#   +------------------+     +------------------+     +------------------+
#   | - Scoring server |     | - Windows DC     |     | - Kali VMs       |
#   | - Owns network   |     | - Windows members|     | - Attack tools   |
#   | - RBAC policies  |     | - Linux servers  |     | - Pentest gear   |
#   +------------------+     +------------------+     +------------------+
#           |                        |                        |
#           +------------------------+------------------------+
#                                    |
#                         [Shared Network: 10.10.10.0/24]
#
# All teams share the same network so Red can attack Blue!
#
# GETTING STARTED:
# ================
# 1. Source credentials:  source ../app-cred-openrc.sh
# 2. Initialize:          tofu init
# 3. Preview changes:     tofu plan
# 4. Deploy:              tofu apply
# 5. Destroy:             tofu destroy
#
# DOCUMENTATION:
# - OpenTofu: https://opentofu.org/docs/
# - OpenStack Provider: https://search.opentofu.org/provider/terraform-provider-openstack/openstack/latest
# - Terraform (compatible): https://developer.hashicorp.com/terraform/docs
#
# ==============================================================================


# ##############################################################################
#                         TERRAFORM/OPENTOFU SETTINGS
# ##############################################################################
# The "terraform" block configures OpenTofu itself.
# This runs BEFORE any resources are created.

terraform {
  required_version = ">= 1.0"
  # Minimum OpenTofu/Terraform version required
  # Prevents using old versions with missing features

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 1.52.1"
      # PROVIDER EXPLAINED:
      # A "provider" is a plugin that knows how to talk to a specific platform.
      # The OpenStack provider translates our .tf code into OpenStack API calls.
      #
      # "source" tells OpenTofu where to download the provider from.
      # "version" ensures compatibility and security updates.
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0"
      # External provider lets us run shell scripts and use their output.
      # Used here for credential validation.
    }
  }
}


# ##############################################################################
#                         OPENSTACK AUTHENTICATION
# ##############################################################################
# Providers need credentials to authenticate with OpenStack.
# We use Application Credentials (more secure than username/password).
#
# SETUP INSTRUCTIONS:
# 1. Download your OpenStack credentials file from the dashboard:
#    Identity → Application Credentials → Download openrc file
# 2. Move the file to the project root and run quick-start.sh
# 3. Before running tofu commands, always source the credentials:
#    source ../app-cred-openrc.sh
#
# The provider automatically reads these environment variables:
# - OS_APPLICATION_CREDENTIAL_ID      (your credential ID)
# - OS_APPLICATION_CREDENTIAL_SECRET  (your credential secret)
# - OS_AUTH_URL                       (OpenStack API endpoint)
#
# WHY APPLICATION CREDENTIALS?
# - More secure than username/password
# - Can be revoked without changing your main password
# - Can have limited permissions (principle of least privilege)
# - Don't expire when you change your password
#
# READ THIS: https://search.opentofu.org/provider/terraform-provider-openstack/openstack/latest


# ##############################################################################
#                         PROVIDER CONFIGURATION
# ##############################################################################
# We configure MULTIPLE providers to deploy to different OpenStack projects.
# This is key to the CTF architecture - each team has their own project!
#
# WHAT IS A PROJECT (TENANT)?
# In OpenStack, a "project" (also called "tenant") is an isolated environment.
# Each project has its own:
# - Quotas (CPU, RAM, storage limits)
# - Users and permissions
# - VMs, networks, and other resources
#
# Teams can only see their own project's resources in the OpenStack dashboard,
# but we share the network so they can communicate (and attack each other!).

# Default provider (main project) - used when no provider is specified
provider "openstack" {
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.main_project_id
  # tenant_id = project ID in OpenStack
  # Find yours: Identity → Projects in the dashboard
}

# Aliased provider for main project (explicit usage)
provider "openstack" {
  alias     = "main"
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.main_project_id

  # ALIAS EXPLAINED:
  # When you have multiple providers of the same type (like 3 OpenStack
  # providers for 3 projects), you give each an "alias" to tell them apart.
  #
  # Usage in resources:
  #   provider = openstack.main   <- Uses this provider
  #   provider = openstack.blue   <- Uses Blue Team provider
  #   provider = openstack.red    <- Uses Red Team provider
}

# Blue Team project provider (Defenders)
provider "openstack" {
  alias     = "blue"
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.blue_project_id

  # BLUE TEAM:
  # Defenders who protect their infrastructure from Red Team attacks.
  # Their Windows and Linux VMs live in this project.
  # They can manage their VMs but can't see Red Team's Kali machines.
}

# Red Team project provider (Attackers)
provider "openstack" {
  alias     = "red"
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.red_project_id

  # RED TEAM:
  # Attackers who try to compromise Blue Team infrastructure.
  # Their Kali Linux attack VMs live in this project.
  # They can manage their VMs but can't see Blue Team's servers.
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

