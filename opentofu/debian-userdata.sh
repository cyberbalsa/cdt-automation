#!/bin/bash
# =============================================================================
# GOAD Deployment VM Cloud-Init Script (Minimal)
# =============================================================================
# Instance: ${instance_num}
# This script only handles:
#   - User creation
#   - SSH configuration
#   - Basic network wait
# All package installation and GOAD setup is handled by Ansible.
# =============================================================================

set -o pipefail

LOGFILE="/var/log/cloud-init-script.log"
INSTANCE_NUM="${instance_num}"

log() {
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $msg" | tee -a "$LOGFILE"
}

# Wait for network connectivity
wait_for_network() {
    log "Waiting for network connectivity..."
    local elapsed=0
    local timeout=120

    while [ $elapsed -lt $timeout ]; do
        if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            log "Network is available"
            return 0
        fi
        sleep 5
        ((elapsed += 5))
    done

    log "Network timeout after $${timeout}s"
    return 1
}

# Wait for cloud-init to release apt locks
wait_for_apt() {
    log "Waiting for apt locks..."
    local max_wait=180
    local elapsed=0

    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if [ $elapsed -ge $max_wait ]; then
            log "Apt lock timeout"
            return 1
        fi
        sleep 5
        ((elapsed += 5))
    done
    return 0
}

# Main setup
main() {
    log "=========================================="
    log "GOAD Deployment VM - Instance $INSTANCE_NUM"
    log "Minimal cloud-init (Ansible handles setup)"
    log "=========================================="

    wait_for_network || log "Network wait failed, continuing..."

    # Create cyberrange user
    log "Creating cyberrange user..."
    if ! id cyberrange &>/dev/null; then
        useradd -m -s /bin/bash cyberrange
    fi
    echo 'cyberrange:Cyberrange123!' | chpasswd
    usermod -aG sudo cyberrange 2>/dev/null || true
    echo "cyberrange ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/cyberrange
    chmod 440 /etc/sudoers.d/cyberrange

    # Configure SSH for password auth (required for Ansible)
    log "Configuring SSH..."
    wait_for_apt || true

    # Ensure openssh-server is installed (usually already present on Ubuntu)
    if ! command -v sshd &>/dev/null; then
        apt-get update -y && apt-get install -y openssh-server
    fi

    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

    # Write instance info for Ansible to use
    mkdir -p /etc/goad
    echo "$INSTANCE_NUM" > /etc/goad/instance_num

    log "=========================================="
    log "Cloud-init complete. Ansible will finish setup."
    log "=========================================="
}

main "$@"
exit 0
