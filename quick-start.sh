#!/bin/bash

# CDT Automation Quick Start Script
# This script helps students get started with the project

set -e  # Exit on any error

echo "🚀 CDT OpenStack Automation - Quick Start"
echo "========================================"

# Detect OS
OS="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
fi

echo "🖥️  Detected OS: $OS"
echo ""

# Check prerequisites
echo "📋 Checking and installing prerequisites..."
echo ""

PACKAGES_TO_INSTALL=()

# Check if OpenTofu is installed
if ! command -v tofu &> /dev/null; then
    echo "❌ OpenTofu not found. Please install it first:"
    echo "   Visit: https://opentofu.org/docs/intro/install/"
    echo "   Quick install (Linux):"
    echo "     curl -fsSL https://get.opentofu.org/install-opentofu.sh | sudo bash"
    exit 1
fi
echo "✅ OpenTofu found: $(tofu version | head -n1)"

# Check if tflint is installed
if ! command -v tflint &> /dev/null; then
    echo "⚠️  tflint not found (recommended for Terraform/OpenTofu linting)"
    echo "   Install with: curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash"
else
    echo "✅ tflint found: $(tflint --version | head -n1)"
fi

# Check if Python3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 not found"
    PACKAGES_TO_INSTALL+=("python3")
else
    echo "✅ Python3 found: $(python3 --version)"
fi

# Check if pip3 is installed
if ! command -v pip3 &> /dev/null; then
    echo "⚠️  pip3 not found"
    if [ "$OS" = "debian" ]; then
        PACKAGES_TO_INSTALL+=("python3-pip")
    fi
else
    echo "✅ pip3 found"
fi

# Check if Ansible is installed
if ! command -v ansible &> /dev/null; then
    echo "⚠️  Ansible not found"
    PACKAGES_TO_INSTALL+=("ansible")
else
    echo "✅ Ansible found: $(ansible --version | head -n1)"
fi

# Check if ansible-lint is installed
if ! command -v ansible-lint &> /dev/null; then
    echo "⚠️  ansible-lint not found (recommended for Ansible linting)"
    PACKAGES_TO_INSTALL+=("ansible-lint")
else
    echo "✅ ansible-lint found: $(ansible-lint --version | head -n1)"
fi

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo "⚠️  sshpass not found (needed for password-based SSH)"
    PACKAGES_TO_INSTALL+=("sshpass")
else
    echo "✅ sshpass found"
fi

# Check if OpenStack CLI is installed
if ! command -v openstack &> /dev/null; then
    echo "⚠️  OpenStack CLI not found (recommended for testing connectivity)"
    if [ "$OS" = "debian" ]; then
        PACKAGES_TO_INSTALL+=("python3-openstackclient")
    fi
else
    echo "✅ OpenStack CLI found"
fi

# Install missing packages if any
if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    echo ""
    echo "📦 Missing packages detected: ${PACKAGES_TO_INSTALL[*]}"
    echo ""

    if [ "$OS" = "debian" ]; then
        echo "Installing packages with apt..."
        read -p "Install missing packages now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo apt update
            sudo apt install -y "${PACKAGES_TO_INSTALL[@]}"
            echo "✅ Packages installed successfully"
        else
            echo "⚠️  Please install missing packages manually:"
            echo "   sudo apt install ${PACKAGES_TO_INSTALL[*]}"
            exit 1
        fi
    elif [ "$OS" = "macos" ]; then
        echo "Please install missing packages with Homebrew:"
        echo "   brew install ansible sshpass"
        exit 1
    else
        echo "Please install missing packages for your OS"
        exit 1
    fi
fi

echo ""
echo "🐍 Checking Python dependencies..."

# Check for required Python packages
PYTHON_PACKAGES=("pywinrm" "requests")
MISSING_PY_PACKAGES=()
APT_PACKAGES=()

for pkg in "${PYTHON_PACKAGES[@]}"; do
    if ! python3 -c "import ${pkg//-/_}" &> /dev/null; then
        echo "⚠️  Python package '$pkg' not found"
        MISSING_PY_PACKAGES+=("$pkg")
        # Map to Debian package names
        if [ "$pkg" = "pywinrm" ]; then
            APT_PACKAGES+=("python3-winrm")
        fi
    else
        echo "✅ Python package '$pkg' found"
    fi
done

# Install missing Python packages
if [ ${#MISSING_PY_PACKAGES[@]} -gt 0 ]; then
    echo ""
    if [ "$OS" = "debian" ] && [ ${#APT_PACKAGES[@]} -gt 0 ]; then
        echo "Installing Python packages via apt: ${APT_PACKAGES[*]}"
        read -p "Install missing Python packages now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo apt install -y "${APT_PACKAGES[@]}"
            echo "✅ Python packages installed successfully"
        else
            echo "⚠️  Please install missing packages manually:"
            echo "   sudo apt install ${APT_PACKAGES[*]}"
        fi
    else
        echo "Installing missing Python packages: ${MISSING_PY_PACKAGES[*]}"
        if pip3 install --user "${MISSING_PY_PACKAGES[@]}" 2>/dev/null; then
            echo "✅ Python packages installed successfully"
        else
            echo "⚠️  pip3 install failed (externally-managed environment)"
            if [ "$OS" = "debian" ]; then
                echo "   Try: sudo apt install python3-winrm"
            fi
            echo "   Or use: pip3 install --user --break-system-packages ${MISSING_PY_PACKAGES[*]}"
            echo ""
            read -p "Continue anyway? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
fi

echo ""
echo "📚 Checking Ansible collections..."

# Check for required Ansible collections
REQUIRED_COLLECTIONS=("ansible.windows" "community.windows")
MISSING_COLLECTIONS=()

for collection in "${REQUIRED_COLLECTIONS[@]}"; do
    if ! ansible-galaxy collection list | grep -q "$collection"; then
        echo "⚠️  Ansible collection '$collection' not found"
        MISSING_COLLECTIONS+=("$collection")
    else
        echo "✅ Ansible collection '$collection' found"
    fi
done

# Install missing Ansible collections
if [ ${#MISSING_COLLECTIONS[@]} -gt 0 ]; then
    echo ""
    echo "Installing missing Ansible collections: ${MISSING_COLLECTIONS[*]}"
    for collection in "${MISSING_COLLECTIONS[@]}"; do
        ansible-galaxy collection install "$collection"
    done
    echo "✅ Ansible collections installed successfully"
fi

echo ""
echo "🔑 Checking SSH configuration..."

# Check SSH key - Must be RSA for Windows compatibility in OpenStack
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "❌ RSA SSH key not found at ~/.ssh/id_rsa"
    echo "   Windows VMs in OpenStack require RSA keys for best compatibility"
    echo "   Generate one with: ssh-keygen -t rsa -b 4096"
    echo "   Press Enter for default location, and optionally set a passphrase"
    exit 1
fi
echo "✅ RSA SSH key found"

# Get the public key fingerprint (use MD5 to match OpenStack format)
if [ -f ~/.ssh/id_rsa.pub ]; then
    # Get both formats for display and comparison
    KEY_FINGERPRINT_SHA256=$(ssh-keygen -lf ~/.ssh/id_rsa.pub 2>/dev/null | awk '{print $2}')
    KEY_FINGERPRINT=$(ssh-keygen -E md5 -lf ~/.ssh/id_rsa.pub 2>/dev/null | awk '{print $2}' | sed 's/MD5://')
    echo "   Key fingerprint (MD5): $KEY_FINGERPRINT"
    echo "   Key fingerprint (SHA256): $KEY_FINGERPRINT_SHA256"
else
    echo "❌ Public key file ~/.ssh/id_rsa.pub not found"
    echo "   Regenerate your key pair with: ssh-keygen -t rsa -b 4096"
    exit 1
fi

echo ""
echo "🔐 Checking OpenStack credentials..."

# Auto-detect and rename credential file
CRED_FILES=(app-cred*openrc.sh)
if [ -f "${CRED_FILES[0]}" ] && [ "${CRED_FILES[0]}" != "app-cred-openrc.sh" ] && [ "${CRED_FILES[0]}" != "app-cred*openrc.sh" ]; then
    echo "📥 Found OpenStack credential file: ${CRED_FILES[0]}"
    echo "   Renaming to: app-cred-openrc.sh"
    mv "${CRED_FILES[0]}" app-cred-openrc.sh
    echo "✅ Credential file renamed successfully"
    echo ""
fi

# Check if app-cred-openrc.sh exists
if [ ! -f "app-cred-openrc.sh" ]; then
    echo "❌ OpenStack credentials file not found"
    echo ""
    echo "   📖 Setting up credentials (EASY METHOD):"
    echo ""
    echo "   1. Go to OpenStack Dashboard:"
    echo "      https://openstack.cyberrange.rit.edu"
    echo ""
    echo "   2. Navigate to: Identity → Application Credentials"
    echo ""
    echo "   3. Click 'Create Application Credential'"
    echo "      - Name: cdt-automation (or any name)"
    echo "      - Click 'Create Application Credential'"
    echo ""
    echo "   4. On the success page, click 'Download openrc file'"
    echo "      (This downloads a shell script with your credentials)"
    echo ""
    echo "   5. Move the downloaded file to this project directory:"
    echo "      mv ~/Downloads/app-cred-*-openrc.sh ."
    echo ""
    echo "   6. Run this script again: ./quick-start.sh"
    echo "      (The script will auto-detect and rename it)"
    echo ""
    echo "   NOTE: Credential files are gitignored and never committed"
    echo ""
    exit 1
fi

# Make sure the file is executable
chmod +x app-cred-openrc.sh

# Source the credentials to set environment variables
echo "Loading OpenStack credentials from app-cred-openrc.sh..."
source app-cred-openrc.sh

# Verify that required environment variables are set
if [ -z "$OS_APPLICATION_CREDENTIAL_ID" ] || [ -z "$OS_APPLICATION_CREDENTIAL_SECRET" ]; then
    echo "❌ OpenStack credentials file is missing required variables"
    echo ""
    echo "   The file app-cred-openrc.sh exists but doesn't set:"
    echo "   - OS_APPLICATION_CREDENTIAL_ID"
    echo "   - OS_APPLICATION_CREDENTIAL_SECRET"
    echo ""
    echo "   Please download the correct file from OpenStack Dashboard:"
    echo "   Identity → Application Credentials → Download openrc file"
    echo ""
    exit 1
fi

echo "✅ OpenStack credentials loaded successfully"

# Test OpenStack connectivity
echo ""
echo "🔗 Testing OpenStack connectivity..."

if ! command -v openstack &> /dev/null; then
    echo "⚠️  OpenStack CLI not installed, skipping connectivity and key import test"
    echo "   Install with: sudo apt install python3-openstackclient (Debian/Ubuntu)"
    echo "   Without OpenStack CLI, you cannot verify if your SSH key is imported"
else
    if timeout 10 openstack project list &> /dev/null; then
        echo "✅ OpenStack connectivity verified"

        # Check if SSH key is imported into OpenStack
        echo ""
        echo "🔑 Checking if SSH key is imported into OpenStack..."

        # Get list of keypairs from OpenStack
        KEYPAIR_LIST=$(openstack keypair list -f value -c Name 2>/dev/null)

        if [ -z "$KEYPAIR_LIST" ]; then
            echo "⚠️  No SSH keys found in OpenStack"
            echo ""
            echo "   You need to import your SSH key into OpenStack:"
            echo "   1. Login to OpenStack Dashboard: https://openstack.cyberrange.rit.edu"
            echo "   2. Go to: Compute → Key Pairs"
            echo "   3. Click 'Import Public Key'"
            echo "   4. Give it a name (e.g., 'my-key' or your username)"
            echo "   5. Paste the contents of: ~/.ssh/id_rsa.pub"
            echo ""
            echo "   Or import via CLI:"
            echo "   openstack keypair create --public-key ~/.ssh/id_rsa.pub <key-name>"
            echo ""
            read -p "Continue anyway? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        else
            echo "✅ Found SSH keys in OpenStack:"
            echo "$KEYPAIR_LIST" | sed 's/^/   - /'
            echo ""
            echo "   Comparing fingerprints (MD5 format):"
            echo "   Local key: $KEY_FINGERPRINT"
            echo ""

            # Show fingerprints of OpenStack keys
            echo "   OpenStack keys:"
            while IFS= read -r keyname; do
                if [ -n "$keyname" ]; then
                    REMOTE_FP=$(openstack keypair show "$keyname" -f value -c fingerprint 2>/dev/null)
                    if [ "$REMOTE_FP" = "$KEY_FINGERPRINT" ]; then
                        echo "   - $keyname: $REMOTE_FP ✅ MATCH"
                    else
                        echo "   - $keyname: $REMOTE_FP"
                    fi
                fi
            done <<< "$KEYPAIR_LIST"

            # Check if any key matches
            MATCHING_KEY=$(openstack keypair list -f value -c Name -c Fingerprint 2>/dev/null | grep "$KEY_FINGERPRINT" | awk '{print $1}')

            if [ -n "$MATCHING_KEY" ]; then
                echo ""
                echo "✅ Your local SSH key matches OpenStack key: $MATCHING_KEY"

                # Check if the keypair name in variables.tf matches
                if [ -f "opentofu/variables.tf" ]; then
                    TOFU_KEYPAIR=$(grep 'variable "keypair"' opentofu/variables.tf -A 1 | grep 'default' | sed -n 's/.*default = "\([^"]*\)".*/\1/p' | head -n1)
                    if [ -n "$TOFU_KEYPAIR" ]; then
                        if [ "$TOFU_KEYPAIR" = "$MATCHING_KEY" ]; then
                            echo "✅ OpenTofu variables.tf is configured to use: $TOFU_KEYPAIR"
                        else
                            echo ""
                            echo "⚠️  WARNING: Keypair name mismatch!"
                            echo "   OpenTofu is configured to use: $TOFU_KEYPAIR"
                            echo "   But your matching key is named: $MATCHING_KEY"
                            echo ""
                            echo "   You should update opentofu/variables.tf:"
                            echo "   variable \"keypair\" { default = \"$MATCHING_KEY\" }"
                            echo ""
                            # Check if the configured keypair exists
                            if echo "$KEYPAIR_LIST" | grep -q "^${TOFU_KEYPAIR}$"; then
                                echo "   Note: '$TOFU_KEYPAIR' exists in OpenStack but doesn't match your local key"
                            else
                                echo "   Note: '$TOFU_KEYPAIR' does NOT exist in OpenStack - deployment will fail!"
                            fi
                            echo ""
                            read -p "Continue anyway? (y/n) " -n 1 -r
                            echo
                            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                                exit 1
                            fi
                        fi
                    fi
                fi
            else
                echo ""
                echo "⚠️  WARNING: Your local key fingerprint doesn't match any OpenStack keys"
                echo "   You may need to import your current key or use a different local key"
                echo ""
                echo "   To import your current key:"
                echo "   openstack keypair create --public-key ~/.ssh/id_rsa.pub <key-name>"
                echo ""
                read -p "Continue anyway? (y/n) " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
        fi
    else
        echo "⚠️  OpenStack connection test failed or timed out"
        echo "   This may be due to network issues or incorrect credentials"
        echo "   Cannot verify SSH key import status"
        echo "   You can continue, but verify your credentials are correct"
        echo ""
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Verify Python import script exists
echo ""
echo "📄 Checking required files..."
if [ ! -f "import-tofu-to-ansible.py" ]; then
    echo "❌ import-tofu-to-ansible.py not found"
    exit 1
fi
echo "✅ import-tofu-to-ansible.py found"

# Check if Python script is executable or can be run
if python3 -m py_compile import-tofu-to-ansible.py 2>/dev/null; then
    echo "✅ import-tofu-to-ansible.py syntax is valid"
else
    echo "⚠️  import-tofu-to-ansible.py has syntax errors"
fi

echo ""
echo "🔧 Initializing OpenTofu..."
echo ""

# Change to opentofu directory and run init
cd opentofu

if tofu init; then
    echo ""
    echo "✅ OpenTofu initialized successfully"
else
    echo ""
    echo "❌ OpenTofu initialization failed"
    echo "   You may need to run 'tofu init' manually in the opentofu directory"
fi

# Return to project root
cd ..

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "🎯 All prerequisites met! You're ready to deploy."
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "📋 Installed Components Summary:"
echo "   ✅ OpenTofu: $(tofu version | head -n1 | cut -d' ' -f2)"
echo "   ✅ Ansible: $(ansible --version | head -n1 | cut -d' ' -f3 | tr -d ']')"
echo "   ✅ Python3: $(python3 --version | cut -d' ' -f2)"
echo "   ✅ sshpass: $(sshpass -V 2>&1 | head -n1 || echo 'installed')"
if command -v openstack &> /dev/null; then
    echo "   ✅ OpenStack CLI: installed"
fi
if command -v tflint &> /dev/null; then
    echo "   ✅ tflint: $(tflint --version | head -n1 | cut -d' ' -f2)"
fi
if command -v ansible-lint &> /dev/null; then
    echo "   ✅ ansible-lint: $(ansible-lint --version | head -n1 | cut -d' ' -f2)"
fi
echo ""
echo "🚀 Next steps:"
echo "   1. Review and customize variables (optional):"
echo "      vim opentofu/variables.tf"
echo ""
echo "   2. (Optional) Run linters to check for issues:"
echo "      ./check.sh"
echo ""
echo "   3. Deploy infrastructure:"
echo "      source app-cred-openrc.sh  # Load credentials"
echo "      cd opentofu"
echo "      tofu plan                   # Preview changes"
echo "      tofu apply                  # Deploy infrastructure"
echo ""
echo "   4. Generate Ansible inventory:"
echo "      cd .."
echo "      python3 import-tofu-to-ansible.py"
echo ""
echo "   5. Configure servers with Ansible:"
echo "      cd ansible"
echo "      ansible-playbook -i inventory.ini site.yml"
echo ""
echo "📖 For detailed instructions, see README.md"
echo ""
echo "💡 Tip: Always run 'source app-cred-openrc.sh' before tofu commands"
echo "💡 Tip: OpenTofu is already initialized - you can go straight to 'tofu plan'"
echo "💡 Tip: Run './check.sh' anytime to lint your Terraform and Ansible code"
echo ""
echo "Happy learning! 🎓"
