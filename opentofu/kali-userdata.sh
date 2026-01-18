#!/bin/bash
# ==============================================================================
# KALI LINUX CLOUD-INIT SCRIPT (Red Team Attack VMs)
# ==============================================================================
# This script runs on first boot to configure Kali for the CTF environment:
#   - Creates cyberrange user with password authentication
#   - Installs and configures xRDP for remote desktop
#   - Sets up XFCE desktop environment
#   - Enables SSH with password authentication
#
# RED TEAM USAGE:
# After boot, you can access Kali via:
#   - SSH: ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<floating_ip>
#   - RDP: Use SSH tunnel, then connect RDP client to localhost:3389
#
# Kali comes pre-loaded with penetration testing tools:
#   - Nmap, Metasploit, Burp Suite, Wireshark
#   - Password crackers (John, Hashcat)
#   - Exploit frameworks and more!
# ==============================================================================

set -o pipefail

# Configuration
LOGFILE="/var/log/cloud-init-script.log"
MAX_RETRIES=5
RETRY_DELAY=10
NETWORK_TIMEOUT=300

# Logging functions
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" | tee -a "$LOGFILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# Retry function with exponential backoff
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local cmd="$*"
    local attempt=1
    local exit_code=0

    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt/$max_attempts: $cmd"
        if eval "$cmd"; then
            log_success "Command succeeded on attempt $attempt"
            return 0
        else
            exit_code=$?
            log_warn "Attempt $attempt failed with exit code $exit_code"
            if [ $attempt -lt $max_attempts ]; then
                local sleep_time=$((delay * attempt))
                log_info "Waiting ${sleep_time}s before retry..."
                sleep "$sleep_time"
            fi
        fi
        ((attempt++))
    done

    log_error "Command failed after $max_attempts attempts: $cmd"
    return $exit_code
}

# Wait for network connectivity
wait_for_network() {
    log_info "Waiting for network connectivity..."
    local elapsed=0
    local check_interval=5

    while [ $elapsed -lt $NETWORK_TIMEOUT ]; do
        if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            log_success "Network is available"
            return 0
        fi
        log_info "Network not ready, waiting... (${elapsed}s/${NETWORK_TIMEOUT}s)"
        sleep $check_interval
        ((elapsed += check_interval))
    done

    log_error "Network not available after ${NETWORK_TIMEOUT}s"
    return 1
}

# Wait for apt lock to be released
wait_for_apt_lock() {
    log_info "Checking for apt locks..."
    local max_wait=300
    local elapsed=0

    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if [ $elapsed -ge $max_wait ]; then
            log_error "Apt lock not released after ${max_wait}s"
            return 1
        fi
        log_info "Apt is locked, waiting... (${elapsed}s)"
        sleep 10
        ((elapsed += 10))
    done

    log_success "No apt locks detected"
    return 0
}

# Update package lists with retry
update_packages() {
    log_info "Updating package lists..."
    wait_for_apt_lock || return 1
    retry_command $MAX_RETRIES $RETRY_DELAY "DEBIAN_FRONTEND=noninteractive apt-get update -y"
}

# Install a package with retry
install_package() {
    local pkg="$1"
    log_info "Installing package: $pkg"
    wait_for_apt_lock || return 1
    retry_command $MAX_RETRIES $RETRY_DELAY \
        "DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' $pkg"
}

# Install multiple packages
install_packages() {
    local packages=("$@")
    log_info "Installing ${#packages[@]} packages..."
    for pkg in "${packages[@]}"; do
        install_package "$pkg" || log_warn "Failed to install $pkg"
    done
}

# Create user
create_user() {
    local username="$1"
    local password="$2"
    local groups="$3"

    log_info "Creating user: $username"

    if id "$username" &>/dev/null; then
        log_info "User $username already exists"
    else
        if ! useradd -m -s /bin/bash -G "$groups" "$username"; then
            log_error "Failed to create user $username"
            return 1
        fi
        log_success "User $username created"
    fi

    # Set password
    if echo "${username}:${password}" | chpasswd; then
        log_success "Password set for $username"
    else
        log_error "Failed to set password for $username"
        return 1
    fi

    return 0
}

# Main execution
main() {
    log_info "=========================================="
    log_info "Red Team Kali Cloud-Init Script Starting"
    log_info "=========================================="

    # Wait for network
    if ! wait_for_network; then
        log_error "Network not available, some operations may fail"
    fi

    # Configure and start SSH
    log_info "Configuring SSH..."
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true

    systemctl enable ssh || systemctl enable sshd || log_warn "Could not enable SSH service"
    systemctl restart ssh || systemctl restart sshd || log_warn "Could not restart SSH service"

    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        log_success "SSH service is running"
    else
        log_error "SSH service failed to start"
    fi

    # Update packages
    update_packages || log_warn "Package update failed, continuing..."

    # Install xRDP and desktop packages
    local packages=(
        xrdp
        xfce4
        xfce4-goodies
        dbus-x11
        openssh-server
        net-tools
        curl
        wget
        git
        vim
        tmux
        htop
    )
    install_packages "${packages[@]}"

    # Create cyberrange user
    create_user "cyberrange" "Cyberrange123!" "sudo,users" || log_warn "User creation had issues"

    # Configure xrdp startwm.sh for XFCE
    cat > /etc/xrdp/startwm.sh << 'STARTWM'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi
exec startxfce4
STARTWM
    chmod 755 /etc/xrdp/startwm.sh

    # Configure xrdp
    log_info "Configuring xrdp..."
    usermod -a -G ssl-cert xrdp 2>/dev/null || log_warn "Could not add xrdp to ssl-cert group"
    systemctl enable xrdp
    systemctl start xrdp

    # Configure xfce4 for cyberrange user
    if [ -d /home/cyberrange ]; then
        echo "xfce4-session" > /home/cyberrange/.xsession
        chown cyberrange:cyberrange /home/cyberrange/.xsession
        log_success "xfce4 session configured for cyberrange"
    fi

    # Set timezone
    timedatectl set-timezone America/New_York 2>/dev/null || log_warn "Could not set timezone"

    log_info "=========================================="
    log_success "Red Team Kali Cloud-Init Script Complete"
    log_info "=========================================="
    log_info "Access:"
    log_info "  SSH: ssh cyberrange@<floating_ip>"
    log_info "  RDP: Connect to port 3389 (xRDP with XFCE)"
    log_info "  Password: Cyberrange123!"
    log_info "=========================================="

    return 0
}

# Run main function
main "$@"
exit $?
