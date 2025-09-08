#!/bin/bash

# CDT Automation Quick Start Script
# This script helps students get started with the project

set -e  # Exit on any error

echo "🚀 CDT OpenStack Automation - Quick Start"
echo "========================================"

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check if OpenTofu is installed
if ! command -v tofu &> /dev/null; then
    echo "❌ OpenTofu not found. Please install it first:"
    echo "   Visit: https://opentofu.org/docs/intro/install/"
    exit 1
fi
echo "✅ OpenTofu found: $(tofu version)"

# Check if Ansible is installed
if ! command -v ansible &> /dev/null; then
    echo "❌ Ansible not found. Please install it first:"
    echo "   Ubuntu/Debian: sudo apt install ansible"
    echo "   macOS: brew install ansible"
    exit 1
fi
echo "✅ Ansible found: $(ansible --version | head -n1)"

# Check SSH key
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "❌ SSH key not found at ~/.ssh/id_rsa"
    echo "   Generate one with: ssh-keygen -t rsa -b 4096"
    exit 1
fi
echo "✅ SSH key found"

# Check OpenStack credentials
if [ ! -f "app-cred-cdtadmin-fffics-openrc.sh" ]; then
    echo "⚠️  OpenStack credentials not found"
    echo "   1. Create application credentials in OpenStack dashboard:"
    echo "      https://openstack.cyberrange.rit.edu → Identity → Application credentials"
    echo "   2. Create a new file called: "
    echo "              app-cred-openrc.sh"
    echo "   3. Edit it with your actual credentials"
    echo "   4. Also update opentofu/main.tf with the same credentials"
    echo "   5. Run this script again"
    exit 1
fi

# Check if main.tf still has placeholder values
if grep -q "YOUR_APPLICATION_CREDENTIAL" opentofu/main.tf; then
    echo "⚠️  OpenTofu configuration needs your credentials"
    echo "   Edit opentofu/main.tf and replace:"
    echo "   - YOUR_APPLICATION_CREDENTIAL_ID_HERE"
    echo "   - YOUR_APPLICATION_CREDENTIAL_SECRET_HERE"
    echo "   With your actual credentials from OpenStack dashboard"
    exit 1
fi

# Source credentials
echo "🔐 Loading OpenStack credentials..."
source app-cred-openrc.sh

# Test OpenStack connectivity
echo "🔗 Testing OpenStack connectivity..."
if ! command -v openstack &> /dev/null; then
    echo "⚠️  OpenStack CLI not found, skipping connectivity test"
else
    if openstack project list &> /dev/null; then
        echo "✅ OpenStack connectivity verified"
    else
        echo "❌ OpenStack connection failed. Check your credentials."
        exit 1
    fi
fi

echo ""
echo "🎯 All prerequisites met! You're ready to deploy."
echo ""
echo "Next steps:"
echo "1. Review and customize variables: vim opentofu/variables.tf"
echo "2. Deploy infrastructure: cd opentofu && tofu init && tofu apply"
echo "3. Configure servers: cd ../ansible && ansible-playbook -i inventory.ini site.yml"
echo ""
echo "📖 For detailed instructions, see README.md"
echo ""
echo "Happy learning! 🎓"
