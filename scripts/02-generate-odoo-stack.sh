#!/bin/bash
################################################################################
# Docker Compose Stack Generator for Odoo
# Purpose: Generate Docker Compose configuration for Odoo + PostgreSQL
#
# This script creates:
# - Docker Compose YAML file
# - Environment file template (.env.example)
# - Directory structure for addons and data
#
# Supports multiple environments (dev, test, prod)
#
# Author: Petr
# Version: 1.2
# Last Updated: March 2026
# Changes:
#   v1.2: Added version pinning with digests and VERSION.txt tracking
#   v1.1: Fixed sessions volume, addons path, and proxy-mode syntax
#   v1.0: Initial release
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION
################################################################################

# Default values (can be overridden via environment variables or CLI args)
ENVIRONMENT=${ENVIRONMENT:-test}           # Environment: test, prod, dev
PROJECT_NAME=${PROJECT_NAME:-odoo}         # Docker Compose project name
ODOO_VERSION=${ODOO_VERSION:-18.0}         # Odoo major version
ODOO_IMAGE_TAG=${ODOO_IMAGE_TAG:-18.0-20260217}  # Specific image tag (ALWAYS use dated tags for stability!)
ODOO_IMAGE_DIGEST=${ODOO_IMAGE_DIGEST:-""} # Optional: Pin to specific digest for absolute version control
POSTGRES_VERSION=${POSTGRES_VERSION:-16}   # PostgreSQL major version
POSTGRES_IMAGE_TAG=${POSTGRES_IMAGE_TAG:-16}  # PostgreSQL image tag
POSTGRES_IMAGE_DIGEST=${POSTGRES_IMAGE_DIGEST:-""}  # Optional: PostgreSQL digest
ODOO_PORT=${ODOO_PORT:-8069}               # Odoo port
DB_PORT=${DB_PORT:-5432}                   # PostgreSQL port (internal to network)

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOY_DIR="${PROJECT_ROOT}/docker/${ENVIRONMENT}"
ADDONS_DIR="${PROJECT_ROOT}/addons"  # Central addons location for all environments
DEPLOY_ADDONS_DIR="${DEPLOY_DIR}/addons"  # Symlinks for Docker compose

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

Generate Docker Compose configuration for Odoo deployment.

OPTIONS:
    -e, --environment ENV    Environment name (test, prod, dev) [default: test]
    -p, --port PORT          Odoo port [default: 8069]
    -n, --project-name NAME  Docker Compose project name [default: odoo]
    -h, --help               Show this help message

EXAMPLES:
    # Generate for test environment
    $0 --environment test

    # Generate for production with custom port
    $0 --environment prod --port 8070

ENVIRONMENT VARIABLES:
    ENVIRONMENT              Environment name
    ODOO_VERSION             Odoo version (default: 18.0)
    POSTGRES_VERSION         PostgreSQL version (default: 16)
    ODOO_PORT                Odoo port
    PROJECT_NAME             Docker Compose project name

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--port)
                ODOO_PORT="$2"
                shift 2
                ;;
            -n|--project-name)
                PROJECT_NAME="$2"
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
    if [[ ! "$ENVIRONMENT" =~ ^(test|prod|dev)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT. Must be: test, prod, or dev"
        exit 1
    fi

    log_info "Configuration:"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Project name: $PROJECT_NAME"
    log_info "  Odoo image: odoo:${ODOO_IMAGE_TAG}"
    if [[ -n "$ODOO_IMAGE_DIGEST" ]]; then
        log_info "  Odoo digest: ${ODOO_IMAGE_DIGEST:0:20}..."
    fi
    log_info "  PostgreSQL image: postgres:${POSTGRES_IMAGE_TAG}"
    log_info "  Odoo port: $ODOO_PORT"
}

# Create directory structure
create_directories() {
    log_step "Creating directory structure..."

    # Create main directories
    mkdir -p "$DEPLOY_DIR"
    mkdir -p "${ADDONS_DIR}"/{custom,oca,cybrosys}
    mkdir -p "${PROJECT_ROOT}/backups/scripts"
    mkdir -p "${PROJECT_ROOT}/chatbot"

    # Create symlinks in deploy directory for Docker compose
    mkdir -p "${DEPLOY_ADDONS_DIR}"

    # Create symlinks if they don't exist
    for addon_type in oca cybrosys custom; do
        if [[ ! -e "${DEPLOY_ADDONS_DIR}/${addon_type}" ]]; then
            ln -s "${ADDONS_DIR}/${addon_type}" "${DEPLOY_ADDONS_DIR}/${addon_type}"
            log_info "Created symlink: ${DEPLOY_ADDONS_DIR}/${addon_type} -> ${ADDONS_DIR}/${addon_type}"
        fi
    done

    log_info "Directories created:"
    log_info "  $DEPLOY_DIR"
    log_info "  ${ADDONS_DIR}/custom"
    log_info "  ${ADDONS_DIR}/oca"
    log_info "  ${ADDONS_DIR}/cybrosys"
    log_info "  ${PROJECT_ROOT}/backups/scripts"
    log_info "  ${PROJECT_ROOT}/chatbot"
}

# Generate docker-compose.yml
generate_docker_compose() {
    log_step "Generating docker-compose.yml..."

    # Build image references with optional digest pinning
    local postgres_image="postgres:${POSTGRES_IMAGE_TAG}"
    if [[ -n "$POSTGRES_IMAGE_DIGEST" ]]; then
        postgres_image="${postgres_image}@${POSTGRES_IMAGE_DIGEST}"
    fi

    local odoo_image="odoo:${ODOO_IMAGE_TAG}"
    if [[ -n "$ODOO_IMAGE_DIGEST" ]]; then
        odoo_image="${odoo_image}@${ODOO_IMAGE_DIGEST}"
    fi

    cat > "${DEPLOY_DIR}/docker-compose.yml" << EOF
# Docker Compose configuration for Odoo ${ODOO_VERSION}
# Environment: ${ENVIRONMENT}
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
#
# VERSION PINNING: Images are pinned to specific tags for stability
# DO NOT update images without thorough testing on test environment first
# See VERSION.txt for version history and testing notes
#
# Customer deployments should NEVER use floating tags like "odoo:18.0"
# Always use dated tags like "odoo:18.0-20260217" to prevent unexpected updates

services:
  db:
    image: ${postgres_image}
    container_name: \${COMPOSE_PROJECT_NAME:-odoo}-${ENVIRONMENT}-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${POSTGRES_USER:-odoo}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD:-changeme}
      POSTGRES_DB: \${POSTGRES_DB:-${ENVIRONMENT}}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - odoo-db-data:/var/lib/postgresql/data/pgdata
    networks:
      - odoo-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER:-odoo}"]
      interval: 10s
      timeout: 5s
      retries: 5

  odoo:
    image: ${odoo_image}
    container_name: \${COMPOSE_PROJECT_NAME:-odoo}-${ENVIRONMENT}
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "\${ODOO_PORT:-${ODOO_PORT}}:8069"
    environment:
      HOST: db
      PORT: 5432
      USER: \${POSTGRES_USER:-odoo}
      PASSWORD: \${POSTGRES_PASSWORD:-changeme}
      DATABASE: \${POSTGRES_DB:-${ENVIRONMENT}}
      # Proxy settings (Caddy reverse proxy)
      PROXY_MODE: "true"
    volumes:
      - odoo-filestore:/var/lib/odoo/filestore
      # Note: sessions volume removed due to permissions issues
      # Odoo will use in-memory sessions (acceptable for most use cases)
      # If persistent sessions are needed, uncomment below and fix permissions
      # - odoo-sessions:/var/lib/odoo/sessions
      # Addons volumes (uncomment after adding modules)
      # Note: These must exist and be valid Odoo addon directories
      # - ./addons/oca:/mnt/addons/oca:ro
      # - ./addons/cybrosys:/mnt/addons/cybrosys:ro
      # - ./addons/custom:/mnt/addons/custom:ro
      # Uncomment for development (read-write access)
      # - ./addons/oca:/mnt/addons/oca:rw
      # - ./addons/cybrosys:/mnt/addons/cybrosys:rw
      # - ./addons/custom:/mnt/addons/custom:rw
    networks:
      - odoo-network
    command: --
      --data-dir=/var/lib/odoo
      --http-interface=0.0.0.0
      --http-port=8069
      --proxy-mode
      --without-demo=all
      # Uncomment when you have modules in addons directories:
      # --addons-path=/mnt/addons/oca,/mnt/addons/cybrosys,/mnt/addons/custom
      --db-filter=^\${POSTGRES_DB:-${ENVIRONMENT}}$$

networks:
  odoo-network:
    driver: bridge
    name: \${COMPOSE_PROJECT_NAME:-odoo}-${ENVIRONMENT}-network

volumes:
  odoo-db-data:
    name: \${COMPOSE_PROJECT_NAME:-odoo}-${ENVIRONMENT}-db-data
  odoo-filestore:
    name: \${COMPOSE_PROJECT_NAME:-odoo}-${ENVIRONMENT}-filestore
  # Sessions volume removed due to permissions issues
  # odoo-sessions:
  #   name: \${COMPOSE_PROJECT_NAME:-odoo}-${ENVIRONMENT}-sessions
EOF

    log_info "Created: ${DEPLOY_DIR}/docker-compose.yml"
}

# Generate .env.example
generate_env_example() {
    log_step "Generating .env.example..."

    cat > "${DEPLOY_DIR}/.env.example" << EOF
# Docker Compose environment variables for ${ENVIRONMENT}
# Copy this file to .env and update with your values

# Docker Compose project name (unique per environment)
COMPOSE_PROJECT_NAME=${PROJECT_NAME}

# PostgreSQL Configuration
POSTGRES_USER=odoo
POSTGRES_PASSWORD=CHANGE_THIS_PASSWORD_NOW
POSTGRES_DB=${ENVIRONMENT}

# Odoo Configuration
ODOO_PORT=${ODOO_PORT}
ODOO_ADMIN_PASSWORD=CHANGE_THIS_ADMIN_PASSWORD_NOW

# Odoo Master Password (for database management)
ODOO_MASTER_PASSWORD=CHANGE_THIS_MASTER_PASSWORD_NOW
EOF

    log_info "Created: ${DEPLOY_DIR}/.env.example"

    # Check if .env exists
    if [[ ! -f "${DEPLOY_DIR}/.env" ]]; then
        log_warn ".env file not found. Copying .env.example to .env"
        cp "${DEPLOY_DIR}/.env.example" "${DEPLOY_DIR}/.env"
        log_warn "IMPORTANT: Edit ${DEPLOY_DIR}/.env and change all passwords!"
    else
        log_info ".env file already exists. Skipping template copy."
    fi
}

# Create addons README
create_addons_readme() {
    log_step "Creating addons README..."

    cat > "${ADDONS_DIR}/README.md" << EOF
# Odoo Addons Directory

This directory contains all custom and third-party Odoo modules.

## Directory Structure

\`\`\`
addons/
├── custom/          # Your custom modules (git repository)
├── oca/             # OCA modules (git repositories)
│   ├── social/      # OCA/social (mail_gateway_whatsapp)
│   ├── account-financial-tools/
│   └── reporting-engine/
└── cybrosys/        # Cybrosys modules (vendored)
    ├── base_accounting_kit/
    └── base_account_budget/
\`\`\`

## Setup Instructions

### 1. OCA Modules (Development)

For development setup with full git history:

\`\`\`bash
cd addons/oca
git clone https://github.com/OCA/social.git
git clone https://github.com/OCA/account-financial-tools.git
git clone https://github.com/OCA/reporting-engine.git

# Checkout appropriate branch
cd social && git checkout 18.0
cd ../account-financial-tools && git checkout 18.0
cd ../reporting-engine && git checkout 18.0
\`\`\`

### 2. Cybrosys Modules

Copy Cybrosys modules to \`addons/cybrosys/\`:

\`\`\`bash
# For MyClient project, these are already in the repository root:
# - base_accounting_kit/
# - base_account_budget/

# Move them to the proper location:
mv base_accounting_kit addons/cybrosys/
mv base_account_budget addons/cybrosys/
\`\`\`

### 3. Custom Modules

Place your custom modules in \`addons/custom/\`.

## Important Notes

- Addons are mounted as **read-only** in docker-compose.yml for safety
- For development, comment out the \`:ro\` suffix to enable read-write access
- After adding new modules, restart containers: \`docker compose restart\`
- Then upgrade apps in Odoo UI: Apps → Update Apps List
EOF

    log_info "Created: ${ADDONS_DIR}/README.md"
}

# Create VERSION.txt for version tracking
create_version_file() {
    log_step "Creating VERSION.txt for version tracking..."

    # Get digests if not provided (optional, requires docker to be installed)
    local odoo_digest="$ODOO_IMAGE_DIGEST"
    local pg_digest="$POSTGRES_IMAGE_DIGEST"

    if [[ -z "$odoo_digest" ]] && command -v docker &> /dev/null; then
        log_info "Fetching Odoo image digest (optional, requires internet)..."
        if odoo_digest=$(docker image inspect "odoo:${ODOO_IMAGE_TAG}" 2>/dev/null | grep -oP 'Digest".*?\Kss256:[^"]*' | head -1); then
            log_info "Found digest for odoo:${ODOO_IMAGE_TAG}"
        fi
    fi

    cat > "${DEPLOY_DIR}/VERSION.txt" << EOF
# Docker Image Version Tracking
# Environment: ${ENVIRONMENT}
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
#
# IMPORTANT: This file tracks tested and working Docker images for this environment.
# DO NOT update images without testing on test environment first!
#
# Update Policy:
# 1. Test new images on test environment for at least 1-2 weeks
# 2. Only update production after test passes
# 3. Document all updates in the "Update History" section
# 4. Keep backup of old images for rollback
#
# ===============================================================================
# Customer Information (for production environments)
# ===============================================================================
Customer: __FILL_IN_CUSTOMER_NAME__
Email: __FILL_IN_CUSTOMER_EMAIL__
Phone: __FILL_IN_CUSTOMER_PHONE__
Domain: __FILL_IN_CUSTOMER_DOMAIN__

# ===============================================================================
# Current Images (Pinned for Stability)
# ===============================================================================

## Odoo Image
Tag: odoo:${ODOO_IMAGE_TAG}
EOF

    if [[ -n "$odoo_digest" ]]; then
        cat >> "${DEPLOY_DIR}/VERSION.txt" << EOF
Digest: ${odoo_digest}

# To pin absolutely to this version, use in docker-compose.yml:
# image: odoo:${ODOO_IMAGE_TAG}@${odoo_digest}
EOF
    else
        cat >> "${DEPLOY_DIR}/VERSION.txt" << EOF
Digest: Not specified (add for absolute pinning)

# To get digest: docker image inspect odoo:${ODOO_IMAGE_TAG} | grep Digest
# Then add to script: ODOO_IMAGE_DIGEST="sha256:..."
EOF
    fi

    cat >> "${DEPLOY_DIR}/VERSION.txt" << EOF

## PostgreSQL Image
Tag: postgres:${POSTGRES_IMAGE_TAG}
EOF

    if [[ -n "$pg_digest" ]]; then
        cat >> "${DEPLOY_DIR}/VERSION.txt" << EOF
Digest: ${pg_digest}

# To pin absolutely to this version, use in docker-compose.yml:
# image: postgres:${POSTGRES_IMAGE_TAG}@${pg_digest}
EOF
    else
        cat >> "${DEPLOY_DIR}/VERSION.txt" << EOF
Digest: Not specified (add for absolute pinning)

# To get digest: docker image inspect postgres:${POSTGRES_IMAGE_TAG} | grep Digest
EOF
    fi

    cat >> "${DEPLOY_DIR}/VERSION.txt" << EOF

# ===============================================================================
# Update History
# ===============================================================================

## $(date -u +"%Y-%m-%d") - Initial Deployment
- Odoo: odoo:${ODOO_IMAGE_TAG}
- PostgreSQL: postgres:${POSTGRES_IMAGE_TAG}
- Status: Initial setup
- Tested: __FILL_IN_TEST_DATE__
- Approved by: __FILL_IN_YOUR_NAME__

# ===============================================================================
# Rollback Information
# ===============================================================================

## To rollback to previous version:
1. Stop containers: docker compose down
2. Edit docker-compose.yml to use previous image tag
3. Pull previous image: docker pull <previous-image>
4. Start containers: docker compose up -d
5. Verify functionality

## To save current image for backup:
docker save odoo:${ODOO_IMAGE_TAG} -o ~/backups/odoo-${ODOO_IMAGE_TAG}-$(date +%Y%m%d).tar.gz
docker save postgres:${POSTGRES_IMAGE_TAG} -o ~/backups/postgres-${POSTGRES_IMAGE_TAG}-$(date +%Y%m%d).tar.gz

## To restore from backup:
docker load -i ~/backups/odoo-<tag>-<date>.tar.gz
EOF

    log_info "Created: ${DEPLOY_DIR}/VERSION.txt"
    log_warn "IMPORTANT: Edit ${DEPLOY_DIR}/VERSION.txt and fill in customer details"
}

# Show summary
show_summary() {
    echo ""
    log_info "=== Docker Compose Stack Generated ==="
    echo ""
    log_info "Files created:"
    log_info "  ${DEPLOY_DIR}/docker-compose.yml"
    log_info "  ${DEPLOY_DIR}/.env.example"
    log_info "  ${DEPLOY_DIR}/VERSION.txt"
    log_info "  ${ADDONS_DIR}/README.md"
    echo ""
    log_warn "IMPORTANT: Next steps:"
    echo "  1. Edit ${DEPLOY_DIR}/.env and set secure passwords"
    echo "  2. Edit ${DEPLOY_DIR}/VERSION.txt and fill in customer details"
    echo "  3. Set up OCA modules in ${ADDONS_DIR}/oca/"
    echo "  4. Move Cybrosys modules to ${ADDONS_DIR}/cybrosys/"
    echo "  5. Symlinks auto-created: ${DEPLOY_ADDONS_DIR}/* -> ${ADDONS_DIR}/*"
    echo "  6. Start the stack: cd ${DEPLOY_DIR} && docker compose up -d"
    echo "  7. Check logs: docker compose logs -f"
    echo ""
    log_info "Stack will be available at: http://localhost:${ODOO_PORT}"
    echo ""
    log_warn "Version pinning enabled with tag: ${ODOO_IMAGE_TAG}"
    log_warn "To add digest pinning, run: docker image inspect odoo:${ODOO_IMAGE_TAG} | grep Digest"
    log_warn "Then re-run this script with ODOO_IMAGE_DIGEST variable set"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=========================================="
    log_info "Docker Compose Stack Generator"
    log_info "=========================================="
    echo ""

    parse_args "$@"

    read -p "Continue generating Docker Compose stack? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi

    create_directories
    generate_docker_compose
    generate_env_example
    create_addons_readme
    create_version_file
    show_summary

    log_info "Next step: Configure environment and start stack"
}

main "$@"
