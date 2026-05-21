#!/bin/bash
################################################################################
# Master Deployment Script - Odoo on Docker
# Purpose: One-command setup for complete Odoo deployment
#
# This script orchestrates all deployment scripts in sequence.
# Suitable for fresh droplet setup and customer onboarding.
#
# Author: Petr
# Version: 1.0
# Last Updated: March 2026
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION
################################################################################

# Customer configuration
CUSTOMER_NAME=${CUSTOMER_NAME:-myclient}
ENVIRONMENT=${ENVIRONMENT:-test}
DOMAIN=${DOMAIN:-}
ODOO_PORT=${ODOO_PORT:-8069}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Options
SKIP_SWAP=${SKIP_SWAP:-false}
SKIP_DOCKER=${SKIP_DOCKER:-false}
_SKIP_CADDY=${SKIP_CADDY:-false}
SKIP_OCA=${SKIP_OCA:-false}
START_SERVICES=${START_SERVICES:-true}
INTERACTIVE=${INTERACTIVE:-true}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
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

log_section() {
    echo ""
    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${MAGENTA}$1${NC}"
    echo -e "${MAGENTA}========================================${NC}"
    echo ""
}

################################################################################
# ERROR HANDLING
################################################################################

handle_error() {
    log_error "Deployment failed at step: $1"
    log_error "Check the error messages above for details"

    echo ""
    log_error "=== Deployment Failed ==="
    log_info "You can retry failed steps individually:"
    log_info "  $0 --step STEP_NAME"
    log_info ""
    log_info "Available steps:"
    log_info "  swap      - Configure swap and system limits"
    log_info "  docker    - Install Docker and Docker Compose"
    log_info "  stack     - Generate Docker Compose stack"
    log_info "  addons    - Set up OCA modules"
    log_info "  caddy     - Configure Caddy reverse proxy"
    log_info "  all       - Run all steps (default)"

    exit 1
}

trap 'handle_error ${STEP:-unknown}' ERR

################################################################################
# FUNCTIONS
################################################################################

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Master deployment script for complete Odoo on Docker setup.

OPTIONS:
    -c, --customer NAME         Customer name [default: myclient]
    -e, --environment ENV       Environment: test, prod [default: test]
    -d, --domain DOMAIN         Domain name (for Caddy)
    -p, --port PORT             Odoo port [default: 8069]
    -s, --step STEP             Run specific step only
    --skip-swap                 Skip swap configuration
    --skip-docker               Skip Docker installation
    --skip-caddy                Skip Caddy configuration
    --skip-addons               Skip OCA modules setup
    --no-start                  Don't start services
    --non-interactive           Run without prompts
    -h, --help                  Show this help message

EXAMPLES:
    # Full deployment for test environment
    sudo $0 --customer myclient --environment test

    # Production deployment with custom port
    sudo $0 --environment prod --port 8070

    # Run only swap configuration
    sudo $0 --step swap

    # Non-interactive deployment
    sudo $0 --non-interactive --environment test

DEPLOYMENT STEPS:
    1. System preparation (swap, limits)
    2. Docker installation
    3. Docker Compose stack generation
    4. OCA modules setup
    5. Caddy reverse proxy configuration
    6. Start services (optional)

REQUIREMENTS:
    - Ubuntu/Debian system
    - Root or sudo access
    - Internet connection
    - Sufficient disk space

ESTIMATED TIME:
    - Fresh droplet: 15-20 minutes
    - Individual steps: 2-5 minutes each

EOF
}

# Parse command line arguments
parse_args() {
    SPECIFIC_STEP=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--customer)
                CUSTOMER_NAME="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -p|--port)
                ODOO_PORT="$2"
                shift 2
                ;;
            -s|--step)
                SPECIFIC_STEP="$2"
                shift 2
                ;;
            --skip-swap)
                SKIP_SWAP=true
                shift
                ;;
            --skip-docker)
                SKIP_DOCKER=true
                shift
                ;;
            --skip-caddy)
                SKIP_CADDY=true
                shift
                ;;
            --skip-addons)
                SKIP_OCA=true
                shift
                ;;
            --no-start)
                START_SERVICES=false
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
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
}

# Prompt for confirmation
prompt_continue() {
    if [[ "$INTERACTIVE" == false ]]; then
        return
    fi

    read -p "$1 (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment aborted"
        exit 0
    fi
}

# Step 1: System preparation
step_swap() {
    STEP="swap"
    log_section "Step 1: System Preparation (Swap & Limits)"

    if [[ "$SKIP_SWAP" == true ]]; then
        log_info "Skipped (--skip-swap)"
        return
    fi

    if [[ ! -f "${SCRIPT_DIR}/00-swap-system-setup.sh" ]]; then
        log_error "Script not found: 00-swap-system-setup.sh"
        exit 1
    fi

    bash "${SCRIPT_DIR}/00-swap-system-setup.sh"
}

# Step 2: Docker installation
step_docker() {
    STEP="docker"
    log_section "Step 2: Docker Installation"

    if [[ "$SKIP_DOCKER" == true ]]; then
        log_info "Skipped (--skip-docker)"
        return
    fi

    if [[ ! -f "${SCRIPT_DIR}/01-install-docker.sh" ]]; then
        log_error "Script not found: 01-install-docker.sh"
        exit 1
    fi

    bash "${SCRIPT_DIR}/01-install-docker.sh"
}

# Step 3: Docker Compose stack
step_stack() {
    STEP="stack"
    log_section "Step 3: Docker Compose Stack Generation"

    if [[ ! -f "${SCRIPT_DIR}/02-generate-odoo-stack.sh" ]]; then
        log_error "Script not found: 02-generate-odoo-stack.sh"
        exit 1
    fi

    bash "${SCRIPT_DIR}/02-generate-odoo-stack.sh" \
        --environment "$ENVIRONMENT" \
        --port "$ODOO_PORT"

    log_warn "IMPORTANT: Edit .env file before starting services"
    log_info "  nano docker/${ENVIRONMENT}/.env"
    log_info "  Set secure passwords for POSTGRES_PASSWORD and ODOO_ADMIN_PASSWORD"

    if [[ "$INTERACTIVE" == true ]]; then
        read -p "Press Enter after editing .env file, or Ctrl+C to abort..."
    fi
}

# Step 4: OCA modules
step_addons() {
    STEP="addons"
    log_section "Step 4: OCA Modules Setup"

    if [[ "$SKIP_OCA" == true ]]; then
        log_info "Skipped (--skip-addons)"
        return
    fi

    if [[ ! -f "${SCRIPT_DIR}/04-setup-oca-modules.sh" ]]; then
        log_error "Script not found: 04-setup-oca-modules.sh"
        exit 1
    fi

    bash "${SCRIPT_DIR}/04-setup-oca-modules.sh"
}

# Step 5: Caddy configuration
step_caddy() {
    STEP="caddy"
    log_section "Step 5: Caddy Reverse Proxy Configuration"

    if [[ "$SKIP_CADDY" == true ]]; then
        log_info "Skipped (--skip-caddy)"
        return
    fi

    if [[ -z "$DOMAIN" ]]; then
        log_warn "No domain specified (--domain), skipping Caddy configuration"
        log_info "Configure Caddy later:"
        log_info "  sudo ${SCRIPT_DIR}/03-setup-caddy.sh --domain YOUR_DOMAIN --port $ODOO_PORT"
        return
    fi

    if [[ ! -f "${SCRIPT_DIR}/03-setup-caddy.sh" ]]; then
        log_error "Script not found: 03-setup-caddy.sh"
        exit 1
    fi

    bash "${SCRIPT_DIR}/03-setup-caddy.sh" \
        --domain "$DOMAIN" \
        --port "$ODOO_PORT" \
        --environment "$ENVIRONMENT"
}

# Step 6: Start services
step_start() {
    STEP="start"
    log_section "Step 6: Starting Services"

    if [[ "$START_SERVICES" == false ]]; then
        log_info "Skipped (--no-start)"
        log_info "Start services manually:"
        log_info "  cd docker/${ENVIRONMENT} && docker compose up -d"
        return
    fi

    local compose_file="$(dirname "$SCRIPT_DIR")/docker/${ENVIRONMENT}/docker-compose.yml"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Docker Compose file not found: $compose_file"
        log_info "Generate stack first: $0 --step stack"
        exit 1
    fi

    cd "$(dirname "$SCRIPT_DIR")/docker/${ENVIRONMENT}"

    log_info "Starting Odoo containers..."
    docker compose up -d

    log_info "Waiting for services to be ready..."
    sleep 10

    log_info "Container status:"
    docker compose ps

    log_info "View logs with: docker compose logs -f"
}

# Show deployment summary
show_summary() {
    log_section "Deployment Complete"

    echo ""
    log_info "Customer: $CUSTOMER_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "Odoo Port: $ODOO_PORT"
    echo ""

    if [[ -n "$DOMAIN" ]]; then
        log_info "URL: https://$DOMAIN"
    else
        log_info "URL: http://YOUR-DROPLET-IP:$ODOO_PORT"
        log_warn "Configure Caddy reverse proxy for SSL:"
        log_info "  sudo ${SCRIPT_DIR}/03-setup-caddy.sh --domain YOUR_DOMAIN --port $ODOO_PORT"
    fi
    echo ""

    log_info "Next steps:"
    log_info "  1. Access Odoo and complete initial setup"
    log_info "  2. Install required modules from Apps menu"
    log_info "  3. Configure Caddy reverse proxy (if not done)"
    log_info "  4. Set up automated backups:"
    log_info "     ${SCRIPT_DIR}/backup-odoo.sh backup --environment $ENVIRONMENT"
    log_info "  5. Monitor health:"
    log_info "     ${SCRIPT_DIR}/07-health-check.sh --environment $ENVIRONMENT"
    echo ""

    log_info "Useful commands:"
    log_info "  View logs:     cd docker/${ENVIRONMENT} && docker compose logs -f"
    log_info "  Restart:       cd docker/${ENVIRONMENT} && docker compose restart"
    log_info "  Stop:          cd docker/${ENVIRONMENT} && docker compose down"
    log_info "  Update:        ${SCRIPT_DIR}/05-deploy.sh --environment $ENVIRONMENT"
    log_info "  Backup:        ${SCRIPT_DIR}/backup-odoo.sh backup --environment $ENVIRONMENT"
    echo ""
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=========================================="
    log_info "Odoo on Docker - Master Deployment"
    log_info "=========================================="
    echo ""

    parse_args "$@"

    log_info "Deployment Configuration:"
    log_info "  Customer: $CUSTOMER_NAME"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Domain: ${DOMAIN:-Not set}"
    log_info "  Odoo Port: $ODOO_PORT"
    log_info "  Interactive: $INTERACTIVE"
    echo ""

    # Run specific step or all steps
    if [[ -n "$SPECIFIC_STEP" ]]; then
        log_info "Running specific step: $SPECIFIC_STEP"
        case "$SPECIFIC_STEP" in
            swap)
                step_swap
                ;;
            docker)
                step_docker
                ;;
            stack)
                step_stack
                ;;
            addons)
                step_addons
                ;;
            caddy)
                step_caddy
                ;;
            start)
                step_start
                ;;
            *)
                log_error "Unknown step: $SPECIFIC_STEP"
                log_info "Available steps: swap, docker, stack, addons, caddy, start"
                exit 1
                ;;
        esac
        log_info "Step '$SPECIFIC_STEP' completed"
        exit 0
    fi

    # Full deployment
    prompt_continue "Continue with full deployment?"

    local start_time=$(date +%s)

    step_swap
    step_docker
    step_stack
    step_addons
    step_caddy
    step_start

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    show_summary

    log_info "Total deployment time: $((duration / 60)) minutes $((duration % 60)) seconds"
    log_info "Deployment successful!"
}

main "$@"
