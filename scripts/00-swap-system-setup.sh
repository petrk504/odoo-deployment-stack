#!/bin/bash
################################################################################
# Odoo on Docker - System Preparation Script
# Purpose: Configure Ubuntu/Debian droplet for Docker + Odoo deployment
#
# This script is designed to be REUSABLE across multiple customers.
# Run this as ROOT or with sudo.
#
# Features:
# - Idempotent (safe to run multiple times)
# - Configurable via environment variables
# - Comprehensive error handling
# - Progress logging
#
# Author: Petr
# Version: 1.0
# Last Updated: March 2026
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

################################################################################
# CONFIGURATION - Override with environment variables if needed
################################################################################

# Swap configuration
SWAP_SIZE_GB=${SWAP_SIZE_GB:-2}              # Swap size in GB (default: 2)
SWAP_FILE_PATH=${SWAP_FILE_PATH:-/swapfile}  # Swap file location
SWAPPINESS=${SWAPPINESS:-10}                 # Swappiness (1-100, 10 = swap only at ~90% RAM)

# System limits
MAX_MAP_COUNT=${MAX_MAP_COUNT:-262144}       # Required for Elasticsearch (if needed later)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

################################################################################
# LOGGING FUNCTIONS
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

################################################################################
# ERROR HANDLING
################################################################################

handle_error() {
    log_error "Script failed at line $1"
    log_error "Check the error messages above for details"
    exit 1
}

trap 'handle_error $LINENO' ERR

################################################################################
# FUNCTIONS
################################################################################

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Detect OS and version
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        log_info "Detected OS: $OS $OS_VERSION"
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
}

# Check available disk space
check_disk_space() {
    local required_space_gb=$((SWAP_SIZE_GB + 2))  # Swap + 2GB buffer
    local available_space_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')

    if [[ $available_space_gb -lt $required_space_gb ]]; then
        log_error "Insufficient disk space. Required: ${required_space_gb}GB, Available: ${available_space_gb}GB"
        exit 1
    fi

    log_info "Disk space check passed: ${available_space_gb}GB available"
}

# Display current memory status
show_memory_status() {
    log_info "Current memory status:"
    free -h
    echo ""

    if swapon --show | grep -q .; then
        log_warn "Swap is already configured:"
        swapon --show
    else
        log_info "No swap currently configured"
    fi
    echo ""
}

# Configure swap
configure_swap() {
    log_info "=== Starting swap configuration ==="

    # Check if swap file already exists
    if [[ -f $SWAP_FILE_PATH ]]; then
        log_warn "Swap file already exists at $SWAP_FILE_PATH"

        # Check if it's active
        if swapon --show | grep -q "$SWAP_FILE_PATH"; then
            log_info "Swap is already active. Skipping swap creation."

            # Update swappiness if different
            current_swappiness=$(cat /proc/sys/vm/swappiness)
            if [[ $current_swappiness -ne $SWAPPINESS ]]; then
                log_info "Updating swappiness from $current_swappiness to $SWAPPINESS"
                sysctl vm.swappiness=$SWAPPINESS
                sed -i "s/vm.swappiness=.*/vm.swappiness=$SWAPPINESS/" /etc/sysctl.conf
            fi

            return 0
        else
            log_warn "Swap file exists but not active. Removing and recreating..."
            swapoff $SWAP_FILE_PATH 2>/dev/null || true
            rm -f $SWAP_FILE_PATH
        fi
    fi

    # Allocate swap file
    log_info "Allocating ${SWAP_SIZE_GB}GB swap file at $SWAP_FILE_PATH..."
    fallocate -l "${SWAP_SIZE_GB}G" $SWAP_FILE_PATH

    # Set secure permissions
    log_info "Setting permissions to 600 (root only)..."
    chmod 600 $SWAP_FILE_PATH

    # Mark as swap space
    log_info "Marking file as swap space..."
    mkswap $SWAP_FILE_PATH

    # Enable swap
    log_info "Enabling swap..."
    swapon $SWAP_FILE_PATH

    # Verify swap is active
    if swapon --show | grep -q "$SWAP_FILE_PATH"; then
        log_info "Swap successfully enabled!"
    else
        log_error "Failed to enable swap"
        exit 1
    fi

    # Add to fstab for persistence (check if entry exists)
    if ! grep -q "$SWAP_FILE_PATH" /etc/fstab; then
        log_info "Adding swap entry to /etc/fstab for persistence..."
        echo "$SWAP_FILE_PATH none swap sw 0 0" >> /etc/fstab
    else
        log_info "Swap entry already exists in /etc/fstab"
    fi

    # Configure swappiness
    log_info "Setting swappiness to $SWAPPINESS (swap at ~90% RAM usage)..."
    sysctl vm.swappiness=$SWAPPINESS

    # Make swappiness persistent
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=$SWAPPINESS" >> /etc/sysctl.conf
    else
        sed -i "s/vm.swappiness=.*/vm.swappiness=$SWAPPINESS/" /etc/sysctl.conf
    fi

    log_info "=== Swap configuration complete ==="
}

# Configure system limits for Docker containers
configure_system_limits() {
    log_info "=== Configuring system limits ==="

    # Increase max_map_count (required for some databases/workloads)
    if [[ $(sysctl -n vm.max_map_count) -lt $MAX_MAP_COUNT ]]; then
        log_info "Setting vm.max_map_count to $MAX_MAP_COUNT..."
        sysctl vm.max_map_count=$MAX_MAP_COUNT

        # Make persistent
        if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
            echo "vm.max_map_count=$MAX_MAP_COUNT" >> /etc/sysctl.conf
        else
            sed -i "s/vm.max_map_count=.*/vm.max_map_count=$MAX_MAP_COUNT/" /etc/sysctl.conf
        fi
    else
        log_info "vm.max_map_count already configured"
    fi

    log_info "=== System limits configured ==="
}

# Display final status
show_final_status() {
    echo ""
    log_info "=== Configuration Summary ==="
    echo ""
    log_info "Memory status after configuration:"
    free -h
    echo ""

    log_info "Swap details:"
    swapon --show
    echo ""

    log_info "System parameters:"
    log_info "  vm.swappiness: $(sysctl -n vm.swappiness)"
    log_info "  vm.max_map_count: $(sysctl -n vm.max_map_count)"
    echo ""

    log_info "=== Setup Complete ==="
    log_info "Your droplet is now ready for Docker + Odoo installation"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=========================================="
    log_info "Odoo on Docker - System Preparation"
    log_info "=========================================="
    echo ""

    check_root
    detect_os
    check_disk_space
    show_memory_status

    read -p "Continue with swap configuration? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi

    configure_swap
    configure_system_limits
    show_final_status

    log_info "Next step: Run scripts/01-install-docker.sh to install Docker and Docker Compose"
}

# Run main function
main "$@"
