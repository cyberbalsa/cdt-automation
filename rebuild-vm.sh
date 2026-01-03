#!/bin/bash

# rebuild-vm.sh - Rebuild a specific VM using OpenTofu and run Ansible playbooks
# Usage: ./rebuild-vm.sh <internal_ip or floating_ip>
# Example: ./rebuild-vm.sh 10.10.10.21
# Example: ./rebuild-vm.sh 100.65.4.55

set -e  # Exit on error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOFU_DIR="${SCRIPT_DIR}/opentofu"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
IMPORT_SCRIPT="${SCRIPT_DIR}/import-tofu-to-ansible.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display usage
usage() {
    echo "Usage: $0 <internal_ip or floating_ip>"
    echo ""
    echo "Examples:"
    echo "  $0 10.10.10.21      # Rebuild using internal IP"
    echo "  $0 100.65.4.55      # Rebuild using floating IP"
    echo ""
    exit 1
}

# Check if IP argument is provided
if [ $# -ne 1 ]; then
    log_error "No IP address provided"
    usage
fi

TARGET_IP="$1"
log_info "Target IP: ${TARGET_IP}"

# Change to OpenTofu directory
cd "${TOFU_DIR}"

# Get OpenTofu outputs
log_info "Fetching OpenTofu state..."
TOFU_OUTPUT=$(tofu output -json)

# Function to find VM by IP
find_vm_by_ip() {
    local ip="$1"
    local vm_name=""
    local vm_type=""
    local vm_index=""

    # Check Windows VMs - internal IPs
    local win_internal_ips=$(echo "${TOFU_OUTPUT}" | jq -r '.windows_vm_internal_ips.value[]' 2>/dev/null)
    local win_floating_ips=$(echo "${TOFU_OUTPUT}" | jq -r '.windows_vm_ips.value[]' 2>/dev/null)
    local win_names=$(echo "${TOFU_OUTPUT}" | jq -r '.windows_vm_names.value[]' 2>/dev/null)

    # Check Debian VMs - internal IPs
    local deb_internal_ips=$(echo "${TOFU_OUTPUT}" | jq -r '.debian_vm_internal_ips.value[]' 2>/dev/null)
    local deb_floating_ips=$(echo "${TOFU_OUTPUT}" | jq -r '.debian_vm_ips.value[]' 2>/dev/null)
    local deb_names=$(echo "${TOFU_OUTPUT}" | jq -r '.debian_vm_names.value[]' 2>/dev/null)

    # Search Windows VMs
    local index=0
    while IFS= read -r internal_ip; do
        local floating_ip=$(echo "${win_floating_ips}" | sed -n "$((index + 1))p")
        local name=$(echo "${win_names}" | sed -n "$((index + 1))p")

        if [ "${ip}" == "${internal_ip}" ] || [ "${ip}" == "${floating_ip}" ]; then
            vm_name="${name}"
            vm_type="windows"
            vm_index="${index}"
            break
        fi
        ((index++))
    done <<< "${win_internal_ips}"

    # If not found, search Debian VMs
    if [ -z "${vm_name}" ]; then
        index=0
        while IFS= read -r internal_ip; do
            local floating_ip=$(echo "${deb_floating_ips}" | sed -n "$((index + 1))p")
            local name=$(echo "${deb_names}" | sed -n "$((index + 1))p")

            if [ "${ip}" == "${internal_ip}" ] || [ "${ip}" == "${floating_ip}" ]; then
                vm_name="${name}"
                vm_type="debian"
                vm_index="${index}"
                break
            fi
            ((index++))
        done <<< "${deb_internal_ips}"
    fi

    if [ -z "${vm_name}" ]; then
        log_error "No VM found with IP: ${ip}"
        exit 1
    fi

    echo "${vm_type}:${vm_name}:${vm_index}"
}

# Find the VM
log_info "Searching for VM with IP: ${TARGET_IP}..."
VM_INFO=$(find_vm_by_ip "${TARGET_IP}")
VM_TYPE=$(echo "${VM_INFO}" | cut -d: -f1)
VM_NAME=$(echo "${VM_INFO}" | cut -d: -f2)
VM_INDEX=$(echo "${VM_INFO}" | cut -d: -f3)

log_success "Found VM: ${VM_NAME} (type: ${VM_TYPE}, index: ${VM_INDEX})"

# Determine the resource identifier
RESOURCE_NAME="openstack_compute_instance_v2.${VM_TYPE}[${VM_INDEX}]"
FIP_RESOURCE="openstack_networking_floatingip_associate_v2.${VM_TYPE}_fip_assoc[${VM_INDEX}]"

log_warning "About to rebuild: ${VM_NAME}"
log_warning "Resource: ${RESOURCE_NAME}"
echo ""
read -p "Are you sure you want to rebuild this VM? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Rebuild cancelled"
    exit 0
fi

# Taint the resources to force rebuild
log_info "Tainting resources for rebuild..."
tofu taint "${RESOURCE_NAME}" || log_warning "Resource may already be tainted"

# Apply changes to rebuild the VM
log_info "Rebuilding VM with OpenTofu..."
tofu apply -target="${RESOURCE_NAME}" -target="${FIP_RESOURCE}" -auto-approve

log_success "VM rebuild completed"

# Regenerate Ansible inventory
log_info "Regenerating Ansible inventory..."
cd "${SCRIPT_DIR}"
python3 "${IMPORT_SCRIPT}"

log_success "Ansible inventory regenerated"

# Get the new VM details from inventory
cd "${ANSIBLE_DIR}"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory.ini"

# Extract ansible_host (floating IP) and internal_ip for the VM
ANSIBLE_HOST=$(grep "^${VM_NAME} " "${INVENTORY_FILE}" | awk '{for(i=1;i<=NF;i++) if($i~/ansible_host=/) print $i}' | cut -d= -f2)
INTERNAL_IP=$(grep "^${VM_NAME} " "${INVENTORY_FILE}" | awk '{for(i=1;i<=NF;i++) if($i~/internal_ip=/) print $i}' | cut -d= -f2)

log_info "VM Details:"
log_info "  Name: ${VM_NAME}"
log_info "  Floating IP: ${ANSIBLE_HOST}"
log_info "  Internal IP: ${INTERNAL_IP}"

# Wait for VM to be reachable
log_info "Waiting for VM to come online..."

if [ "${VM_TYPE}" == "windows" ]; then
    # Windows VMs take longer to boot
    log_info "Detected Windows VM - using extended timeout (15 minutes)"
    TIMEOUT=900  # 15 minutes
    RETRY_DELAY=30
    PING_MODULE="ansible.windows.win_ping"
else
    # Linux VMs boot faster
    log_info "Detected Linux VM - using standard timeout (5 minutes)"
    TIMEOUT=300  # 5 minutes
    RETRY_DELAY=10
    PING_MODULE="ansible.builtin.ping"
fi

ELAPSED=0
REACHABLE=false

while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
    log_info "Attempting to connect (elapsed: ${ELAPSED}s / ${TIMEOUT}s)..."

    if ansible "${VM_NAME}" -i "${INVENTORY_FILE}" -m "${PING_MODULE}" &>/dev/null; then
        REACHABLE=true
        break
    fi

    sleep ${RETRY_DELAY}
    ELAPSED=$((ELAPSED + RETRY_DELAY))
done

if [ "${REACHABLE}" = false ]; then
    log_error "VM did not become reachable within ${TIMEOUT} seconds"
    log_error "You may need to check the VM manually"
    exit 1
fi

log_success "VM is online and reachable!"

# Determine which playbooks to run based on VM type and role
log_info "Determining which playbooks to run..."

PLAYBOOKS_TO_RUN=()

if [ "${VM_TYPE}" == "windows" ]; then
    if [ "${VM_INDEX}" == "0" ]; then
        # First Windows VM - Domain Controller
        log_info "VM is the Domain Controller - will run DC setup"
        PLAYBOOKS_TO_RUN+=("setup-domain-controller.yml")
    else
        # Windows member
        log_info "VM is a Windows domain member"
        PLAYBOOKS_TO_RUN+=("join-windows-domain.yml")
    fi
else
    # Linux/Debian member
    log_info "VM is a Linux domain member"
    PLAYBOOKS_TO_RUN+=("join-linux-domain.yml")
    PLAYBOOKS_TO_RUN+=("create-domain-users.yml")
fi

# Run the playbooks
for playbook in "${PLAYBOOKS_TO_RUN[@]}"; do
    log_info "Running playbook: ${playbook}"

    if [ "${VM_TYPE}" == "windows" ] && [ "${VM_INDEX}" == "0" ]; then
        # For DC setup, we need domain variables
        ansible-playbook -i "${INVENTORY_FILE}" \
            --limit "${VM_NAME}" \
            -e "domain_name=CDT" \
            -e "domain_admin_user=Administrator" \
            -e "domain_admin_password=Cyberrange123!" \
            "${playbook}"
    elif [ "${VM_TYPE}" == "windows" ]; then
        # For Windows members
        ansible-playbook -i "${INVENTORY_FILE}" \
            --limit "${VM_NAME}" \
            -e "domain_name=CDT" \
            -e "domain_admin_user=Administrator" \
            -e "domain_admin_password=Cyberrange123!" \
            "${playbook}"
    else
        # For Linux members
        ansible-playbook -i "${INVENTORY_FILE}" \
            --limit "${VM_NAME}" \
            -e "domain_name=CDT" \
            -e "domain_admin_user=Administrator" \
            -e "domain_admin_password=Cyberrange123!" \
            "${playbook}"
    fi

    if [ $? -eq 0 ]; then
        log_success "Playbook ${playbook} completed successfully"
    else
        log_error "Playbook ${playbook} failed"
        exit 1
    fi
done

log_success "=============================================="
log_success "VM Rebuild and Configuration Complete!"
log_success "=============================================="
log_success "VM Name: ${VM_NAME}"
log_success "Type: ${VM_TYPE}"
log_success "Floating IP: ${ANSIBLE_HOST}"
log_success "Internal IP: ${INTERNAL_IP}"
log_success "=============================================="
