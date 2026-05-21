#!/bin/bash
################################################################################
# Complete Odoo 18 Docker Installation Script
# Customer: MyClient Hotel (or your customer)
# Environment: Ubuntu 24.04 + Docker + Odoo 18.0
#
# This script automates the entire setup process based on real-world testing.
#
# Author: Petr
# Version: 1.0
# Last Updated: March 17, 2026
#
# Usage:
#   sudo ./install-odoo-docker.sh [--environment test|prod] [--domain your-domain.com]
#
# Example:
#   sudo ./install-odoo-docker.sh --environment test --domain test.example.com
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION
################################################################################

# Default values
ENVIRONMENT=${ENVIRONMENT:-test}
DOMAIN_NAME=${DOMAIN_NAME:-}
CUSTOMER_NAME=${CUSTOMER_NAME:-"Your Customer Name"}
ADMIN_EMAIL=${ADMIN_EMAIL:-"admin@$(hostname -f)"}

# Docker settings
COMPOSE_PROJECT_NAME="odoo"
ODOO_PORT=8069
POSTGRES_USER="odoo"
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Odoo settings
DATABASE_NAME=$ENVIRONMENT
ODOO_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ODOO_MASTER_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Working directories
WORK_DIR="$HOME/odoo-docker"
ADDONS_DIR="$HOME/addons"
DEPLOY_DIR="$WORK_DIR/$ENVIRONMENT"

# Pinned images (tested and working)
ODOO_IMAGE="odoo:18.0@sha256:f943845750728960f9c3891a7076a72bd257f5b2d50d1c3d993e29a6e06d9489"
POSTGRES_IMAGE="postgres:16"

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
# FUNCTIONS
################################################################################

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Complete Odoo 18 Docker installation for production deployment.

OPTIONS:
    -e, --environment ENV    Environment name (test, prod) [default: test]
    -d, --domain DOMAIN       Domain name for Caddy configuration
    -c, --customer NAME       Customer name [default: Your Customer Name]
    -h, --help               Show this help message

EXAMPLES:
    # Install for test environment
    sudo $0 --environment test --domain test.example.com

    # Install for production
    sudo $0 --environment prod --domain odoo.example.com --customer "Hotel California"

ENVIRONMENT VARIABLES:
    ODOO_PORT                Odoo port [default: 8069]
    POSTGRES_PASSWORD         PostgreSQL password [default: auto-generate]
    DATABASE_NAME             Database name [default: same as environment]

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -d|--domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            -c|--customer)
                CUSTOMER_NAME="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(test|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT. Must be: test or prod"
        exit 1
    fi
}

check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    # Check if docker-compose is installed
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose is not installed. Installing..."
        apt install -y docker-compose
    fi

    log_info "Prerequisites check passed"
}

create_directories() {
    log_step "Creating directory structure..."

    # Create main directories
    mkdir -p "$WORK_DIR"
    mkdir -p "$ADDONS_DIR"/{oca,cybrosys,custom}
    mkdir -p "$DEPLOY_DIR"

    # Fix ownership
    local REAL_USER=${SUDO_USER:-$USER}
    chown -R "$REAL_USER:$REAL_USER" "$WORK_DIR" 2>/dev/null || true
    chown -R "$REAL_USER:$REAL_USER" "$ADDONS_DIR" 2>/dev/null || true

    log_info "Created: $WORK_DIR"
    log_info "Created: $ADDONS_DIR"
    log_info "Created: $DEPLOY_DIR"
}

clone_oca_modules() {
    log_step "Downloading OCA modules..."

    # Check if git is installed
    if ! command -v git &> /dev/null; then
        log_warn "Git not found. Installing git..."
        apt install -y git
    fi

    # Clone OCA repositories
    local oca_repos=(
        "social"
        "account-financial-tools"
        "reporting-engine"
    )

    for repo in "${oca_repos[@]}"; do
        if [[ ! -d "$ADDONS_DIR/oca/$repo" ]]; then
            log_info "Cloning OCA/$repo..."
            git clone -q --depth 1 --branch 18.0 \
                "https://github.com/OCA/$repo.git" \
                "$ADDONS_DIR/oca/$repo" 2>/dev/null || {
                log_warn "Failed to clone $repo, skipping..."
            }
        else
            log_info "OCA/$repo already exists, skipping..."
        fi
    done

    log_info "OCA modules downloaded"
}

copy_cybrosys_modules() {
    log_step "Copying Cybrosys modules..."

    # These should be in the current directory or a known location
    if [[ -d "base_accounting_kit" ]]; then
        cp -r base_accounting_kit "$ADDONS_DIR/cybrosys/"
        log_info "Copied: base_accounting_kit"
    fi

    if [[ -d "base_account_budget" ]]; then
        cp -r base_account_budget "$ADDONS_DIR/cybrosys/"
        log_info "Copied: base_account_budget"
    fi

    log_info "Cybrosys modules copied"
}

create_docker_compose() {
    log_step "Creating Docker Compose configuration..."

    cat > "$DEPLOY_DIR/docker-compose.yml" << EOF
# Docker Compose configuration for Odoo 18.0
# Environment: $ENVIRONMENT
# Customer: $CUSTOMER_NAME
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
#
# VERSION PINNING: Using tested working image
# Image: $ODOO_IMAGE
# Created: 2026-02-17 (tested and working)
#
# IMPORTANT: This configuration has been tested and validated.
# DO NOT change the image digest without thorough testing.

services:
  db:
    image: $POSTGRES_IMAGE
    container_name: \${COMPOSE_PROJECT_NAME:-$COMPOSE_PROJECT_NAME}-${ENVIRONMENT}-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${POSTGRES_USER:-$POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD:-$POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - \${COMPOSE_PROJECT_NAME:-$COMPOSE_PROJECT_NAME}-${ENVIRONMENT}-db-data:/var/lib/postgresql/data/pgdata
    networks:
      - odoo-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER:-$POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  odoo:
    image: $ODOO_IMAGE
    container_name: \${COMPOSE_PROJECT_NAME:-$COMPOSE_PROJECT_NAME}-${ENVIRONMENT}
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "\${ODOO_PORT:-$ODOO_PORT}:8069"
    environment:
      HOST: db
      PORT: 5432
      USER: \${POSTGRES_USER:-$POSTGRES_USER}
      PASSWORD: \${POSTGRES_PASSWORD:-$POSTGRES_PASSWORD}
      DATABASE: $DATABASE_NAME
      PROXY_MODE: "true"
    volumes:
      - \${COMPOSE_PROJECT_NAME:-$COMPOSE_PROJECT_NAME}-${ENVIRONMENT}-filestore:/var/lib/odoo/filestore
    networks:
      - odoo-network
    command: --
      --data-dir=/var/lib/odoo
      --http-interface=0.0.0.0
      --http-port=8069
      --proxy-mode
      --without-demo=all
      --db-filter=^${DATABASE_NAME}$$

networks:
  odoo-network:
    driver: bridge
    name: \${COMPOSE_PROJECT_NAME:-$COMPOSE_PROJECT_NAME}-${ENVIRONMENT}-network

volumes:
  \${COMPOSE_PROJECT_NAME:-$COMPOSE_PROJECT_NAME}-${ENVIRONMENT}-db-data:
  \${COMPOSE_PROJECT_NAME:-$COMPOSE_PROJECT_NAME}-${ENVIRONMENT}-filestore:
EOF

    log_info "Created: $DEPLOY_DIR/docker-compose.yml"
}

create_env_file() {
    log_step "Creating environment file..."

    cat > "$DEPLOY_DIR/.env" << EOF
# Docker Compose environment for $ENVIRONMENT
# Customer: $CUSTOMER_NAME
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Docker Compose project name
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME

# PostgreSQL Configuration
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Odoo Configuration
ODOO_PORT=$ODOO_PORT
DATABASE=$DATABASE_NAME
EOF

    # Fix ownership
    local REAL_USER=${SUDO_USER:-$USER}
    chown "$REAL_USER:$REAL_USER" "$DEPLOY_DIR/.env"

    log_info "Created: $DEPLOY_DIR/.env"
    log_warn "IMPORTANT: Passwords are auto-generated. Save these credentials!"
    log_warn "  PostgreSQL: $POSTGRES_PASSWORD"
    log_warn "  Odoo Admin: $ODOO_ADMIN_PASSWORD"
    log_warn "  Odoo Master: $ODOO_MASTER_PASSWORD"

    # Save credentials to file
    cat > "$WORK_DIR/CREDENTIALS-$ENVIRONMENT.txt" << EOF
# Odoo Credentials - $ENVIRONMENT Environment
# Customer: $CUSTOMER_NAME
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
DATABASE_NAME=$DATABASE_NAME
ODOO_ADMIN_PASSWORD=$ODOO_ADMIN_PASSWORD
ODOO_MASTER_PASSWORD=$ODOO_MASTER_PASSWORD

# Access URLs:
# HTTP: http://localhost:$ODOO_PORT
# Database: http://localhost:$ODOO_PORT/web/database/manager
EOF

    chown "$REAL_USER:$REAL_USER" "$WORK_DIR/CREDENTIALS-$ENVIRONMENT.txt"
}

deploy_stack() {
    log_step "Deploying Odoo stack..."

    cd "$DEPLOY_DIR"

    # Pull images
    log_info "Pulling Docker images..."
    docker-compose pull

    # Start containers
    log_info "Starting containers..."
    docker-compose up -d

    # Wait for startup
    log_info "Waiting for Odoo to start..."
    sleep 20

    # Fix filestore permissions
    log_info "Fixing filestore permissions..."
    docker exec --user root "${COMPOSE_PROJECT_NAME}-${ENVIRONMENT}" \
        chown -R odoo:odoo /var/lib/odoo/filestore

    # Check status
    if docker ps | grep -q "${COMPOSE_PROJECT_NAME}-${ENVIRONMENT}"; then
        log_info "✓ Odoo is running!"
    else
        log_error "✗ Odoo failed to start!"
        docker-compose logs --tail=50
        exit 1
    fi
}

print_summary() {
    echo ""
    log_info "=== Installation Complete ==="
    echo ""
    echo -e "${GREEN}Credentials saved to:${NC} $WORK_DIR/CREDENTIALS-$ENVIRONMENT.txt"
    echo ""
    echo -e "${GREEN}Access URLs:${NC}"
    echo "  HTTP: http://localhost:$ODOO_PORT"
    if [[ -n "$DOMAIN_NAME" ]]; then
        echo "  HTTPS: http://$DOMAIN_NAME"
    fi
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "  1. Open your browser and go to: http://localhost:$ODOO_PORT"
    echo "  2. Click 'Create database'"
    echo "  3. Fill in database details:"
    echo "     - Database name: $DATABASE_NAME"
    echo "     - Email: $ADMIN_EMAIL"
    echo "     - Password: (choose your own)"
    echo "  4. Click 'Create' and wait for initialization (1-2 minutes)"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "  - Credentials are saved in: $WORK_DIR/CREDENTIALS-$ENVIRONMENT.txt"
    echo "  - Make sure to backup this file!"
    echo "  - After database is created, see ADDONS-GUIDE.md to add modules"
    echo ""
    echo -e "${BLUE}Need help?${NC} See: TROUBLESHOOTING.md"
    echo ""
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=========================================="
    log_info "Odoo 18 Docker Installation"
    log_info "Customer: $CUSTOMER_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "=========================================="
    echo ""

    parse_args "$@"
    check_prerequisites
    create_directories
    clone_oca_modules
    copy_cybrosys_modules
    create_docker_compose
    create_env_file
    deploy_stack
    print_summary

    log_info "Installation completed successfully!"
}

main "$@"
