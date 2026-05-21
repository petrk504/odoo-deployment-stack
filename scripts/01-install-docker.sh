#!/bin/bash
################################################################################
# Docker Installation Script for Ubuntu/Debian
# Purpose: Install Docker and Docker Compose for Odoo deployment
#
# This script installs:
# - Docker Engine (latest stable version)
# - Docker Compose (plugin)
# - Adds user to docker group (optional)
#
# Run this as ROOT or with sudo.
#
# Author: Petr
# Version: 1.0
# Last Updated: March 2026
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION
################################################################################

# User to add to docker group (leave empty to skip)
DOCKER_USER=${DOCKER_USER:-""}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

################################################################################
# ERROR HANDLING
################################################################################

handle_error() {
    log_error "Script failed at line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

################################################################################
# FUNCTIONS
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        log_info "Detected OS: $OS $OS_VERSION"
    else
        log_error "Cannot detect OS"
        exit 1
    fi
}

# Check if Docker is already installed
check_docker_installed() {
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
        log_warn "Docker is already installed: version $docker_version"

        read -p "Reinstall Docker anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping Docker installation"
            return 1
        fi
        log_warn "Removing existing Docker installation..."
        apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    fi
    return 0
}

# Install prerequisites
install_prerequisites() {
    log_step "Installing prerequisites..."
    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    log_info "Prerequisites installed"
}

# Add Docker's official GPG key
add_docker_gpg_key() {
    log_step "Adding Docker's official GPG key..."

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${OS}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    log_info "GPG key added"
}

# Set up Docker repository
setup_docker_repo() {
    log_step "Setting up Docker repository..."

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/${OS} \
      $(lsb_release -cs) stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    log_info "Docker repository configured"
}

# Install Docker Engine
install_docker_engine() {
    log_step "Installing Docker Engine, containerd, and Docker Compose..."

    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    log_info "Docker installed successfully"
}

# Start and enable Docker service
start_docker() {
    log_step "Starting Docker service..."
    systemctl enable docker
    systemctl start docker

    # Verify Docker is running
    if docker info &> /dev/null; then
        log_info "Docker service is running"
    else
        log_error "Failed to start Docker service"
        exit 1
    fi
}

# Add user to docker group
add_user_to_docker_group() {
    if [[ -n "$DOCKER_USER" ]]; then
        if id "$DOCKER_USER" &>/dev/null; then
            log_step "Adding user '$DOCKER_USER' to docker group..."
            usermod -aG docker "$DOCKER_USER"
            log_info "User '$DOCKER_USER' added to docker group"
            log_warn "User must log out and back in for group changes to take effect"
        else
            log_warn "User '$DOCKER_USER' does not exist. Skipping."
        fi
    else
        log_info "No user specified for docker group. Skipping."
    fi
}

# Display Docker info
show_docker_info() {
    echo ""
    log_info "=== Docker Installation Summary ==="
    echo ""
    docker --version
    docker compose version
    echo ""

    log_info "Docker system info:"
    docker info | head -n 20
    echo ""

    log_info "Docker is ready to use!"
    log_info "Test with: docker run hello-world"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=========================================="
    log_info "Docker Installation Script"
    log_info "=========================================="
    echo ""

    check_root
    detect_os

    # Set default user if not specified
    if [[ -z "$DOCKER_USER" ]]; then
        if [[ -n "${SUDO_USER:-}" ]]; then
            DOCKER_USER=$SUDO_USER
            log_info "Detected sudo user: $DOCKER_USER"
        fi
    fi

    check_docker_installed || return 0

    read -p "Continue with Docker installation? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi

    install_prerequisites
    add_docker_gpg_key
    setup_docker_repo
    install_docker_engine
    start_docker
    add_user_to_docker_group
    show_docker_info

    log_info "Next step: Run scripts/02-create-odoo-stack.sh to create Docker Compose configuration"
}

main "$@"
