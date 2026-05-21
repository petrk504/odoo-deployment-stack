#!/bin/bash
################################################################################
# Caddy Reverse Proxy Configuration Script
# Purpose: Configure Caddy as reverse proxy for Odoo with automatic SSL
#
# Why Caddy instead of Nginx:
# - Automatic SSL via Let's Encrypt (zero manual config)
# - Proper X-Forwarded-* headers for Microsoft 365 OAuth
# - Simple, human-readable configuration
# - Auto-renewal of certificates
#
# Author: Petr
# Version: 1.0
# Last Updated: March 2026
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION
################################################################################

# Caddy paths
CADDY_CONFIG_DIR="/etc/caddy"
CADDY_FILE="${CADDY_CONFIG_DIR}/Caddyfile"
CADDY_BACKUP_DIR="${CADDY_CONFIG_DIR}/backups"

# Odoo configuration
ENVIRONMENT=${ENVIRONMENT:-test}
DOMAIN=${DOMAIN:-}
ODOO_PORT=${ODOO_PORT:-8069}
ODOO_UPSTREAM=${ODOO_UPSTREAM:-localhost:${ODOO_PORT}}

# Caddy service
CADDY_SERVICE="caddy"

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

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure Caddy reverse proxy for Odoo with automatic SSL.

OPTIONS:
    -d, --domain DOMAIN         Domain name (required)
    -p, --port PORT             Odoo port [default: 8069]
    -e, --environment ENV       Environment: test, prod [default: test]
    -r, --remove                Remove Caddy configuration for domain
    -h, --help                  Show this help message

EXAMPLES:
    # Configure Caddy for test environment
    sudo $0 --domain test.example.com --port 8069

    # Configure Caddy for production
    sudo $0 --domain prod.example.com --port 8070

    # Remove configuration
    sudo $0 --domain test.example.com --remove

REQUIREMENTS:
    - Caddy must be installed
    - Domain DNS must point to this server
    - Ports 80 and 443 must be accessible

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Parse command line arguments
parse_args() {
    REMOVE_CONFIG=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -p|--port)
                ODOO_PORT="$2"
                ODOO_UPSTREAM="localhost:${ODOO_PORT}"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -r|--remove)
                REMOVE_CONFIG=true
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

    if [[ -z "$DOMAIN" && "$REMOVE_CONFIG" == false ]]; then
        log_error "Domain is required (use --domain)"
        show_usage
        exit 1
    fi
}

# Check if Caddy is installed
check_caddy_installed() {
    if ! command -v caddy &> /dev/null; then
        log_error "Caddy is not installed"
        log_info "Install Caddy with:"
        log_info "  sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https"
        log_info "  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
        log_info "  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list"
        log_info "  sudo apt update"
        log_info "  sudo apt install caddy"
        exit 1
    fi

    log_info "Caddy is installed: $(caddy version | head -n1)"
}

# Create backup directory
create_backup_dir() {
    if [[ ! -d "$CADDY_BACKUP_DIR" ]]; then
        mkdir -p "$CADDY_BACKUP_DIR"
        log_info "Created backup directory: $CADDY_BACKUP_DIR"
    fi
}

# Backup existing Caddyfile
backup_caddyfile() {
    if [[ -f "$CADDY_FILE" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="${CADDY_BACKUP_DIR}/Caddyfile_${timestamp}"
        cp "$CADDY_FILE" "$backup_file"
        log_info "Backed up Caddyfile to: $backup_file"
    fi
}

# Generate Caddy configuration block
generate_caddy_block() {
    cat << EOF
${DOMAIN} {
    # Log file
    log {
        output file /var/log/caddy/${ENVIRONMENT}-${DOMAIN}.log
        format json
        level INFO
    }

    # Reverse proxy to Odoo
    reverse_proxy ${ODOO_UPSTREAM} {
        # Health check
        health_uri /web/health
        health_interval 30s
        health_timeout 10s

        # Headers for Odoo
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Real-IP {remote_host}

        # WebSocket support for Odoo bus/websocket
        header_up Connection {>Connection}
        header_up Upgrade {>Upgrade}
    }

    # Security headers
    header {
        # Enable HSTS
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"

        # Prevent clickjacking
        X-Frame-Options "SAMEORIGIN"

        # Prevent MIME type sniffing
        X-Content-Type-Options "nosniff"

        # XSS protection
        X-XSS-Protection "1; mode=block"

        # Referrer policy
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    # Odoo longpolling/worker endpoint (if needed)
    handle /longpolling/* {
        reverse_proxy ${ODOO_UPSTREAM}:8072 {
            header_up X-Forwarded-Host {host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
}
EOF
}

# Add or update Caddy configuration
add_caddy_config() {
    log_step "Adding Caddy configuration for $DOMAIN"

    # Check if domain already exists in Caddyfile
    if grep -q "^${DOMAIN} {" "$CADDY_FILE" 2>/dev/null; then
        log_warn "Configuration for $DOMAIN already exists"

        # Ask before overwriting
        read -p "Update existing configuration? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping configuration update"
            return
        fi

        # Remove existing configuration
        log_info "Removing existing configuration..."
        sed -i "/^${DOMAIN} {/,/^}/d" "$CADDY_FILE"
    fi

    # Add new configuration
    log_info "Adding new configuration block..."
    generate_caddy_block >> "$CADDY_FILE"

    log_info "Configuration added successfully"
}

# Remove Caddy configuration
remove_caddy_config() {
    log_step "Removing Caddy configuration for $DOMAIN"

    if [[ ! -f "$CADDY_FILE" ]]; then
        log_warn "Caddyfile not found: $CADDY_FILE"
        return
    fi

    if grep -q "^${DOMAIN} {" "$CADDY_FILE"; then
        backup_caddyfile
        sed -i "/^${DOMAIN} {/,/^}/d" "$CADDY_FILE"
        log_info "Configuration removed for $DOMAIN"
    else
        log_warn "No configuration found for $DOMAIN"
    fi
}

# Validate Caddy configuration
validate_config() {
    log_step "Validating Caddy configuration..."

    if caddy validate --config "$CADDY_FILE" --adapter caddyfile; then
        log_info "Caddy configuration is valid"
    else
        log_error "Caddy configuration validation failed"
        log_error "Restoring backup..."
        if [[ -f "${CADDY_BACKUP_DIR}/Caddyfile_$(ls -t ${CADDY_BACKUP_DIR}/Caddyfile_* | head -1 | xargs basename)" ]]; then
            cp "${CADDY_BACKUP_DIR}/Caddyfile_$(ls -t ${CADDY_BACKUP_DIR}/Caddyfile_* | head -1 | xargs basename)" "$CADDY_FILE"
        fi
        exit 1
    fi
}

# Reload Caddy service
reload_caddy() {
    log_step "Reloading Caddy service..."

    if systemctl reload caddy; then
        log_info "Caddy reloaded successfully"
    else
        log_error "Failed to reload Caddy"
        exit 1
    fi
}

# Show Caddy status
show_status() {
    echo ""
    log_info "=== Caddy Status ==="
    echo ""

    systemctl status caddy --no-pager | head -n 10
    echo ""

    log_info "Current Caddyfile configuration:"
    if [[ -f "$CADDY_FILE" ]]; then
        grep -A 20 "^${DOMAIN} {" "$CADDY_FILE" || echo "No configuration found for $DOMAIN"
    fi
    echo ""
}

# Check DNS resolution
check_dns() {
    log_step "Checking DNS resolution for $DOMAIN..."

    local server_ip=$(curl -s ifconfig.me)
    local domain_ip=$(dig +short $DOMAIN | grep -E '^[0-9]' | head -1)

    if [[ -z "$domain_ip" ]]; then
        log_warn "DNS does not resolve for $DOMAIN"
        log_warn "SSL certificate will NOT be issued until DNS is configured"
        log_warn "Make sure an A record points $DOMAIN to $server_ip"
        return
    fi

    if [[ "$domain_ip" == "$server_ip" ]]; then
        log_info "DNS correctly configured: $DOMAIN → $domain_ip"
    else
        log_warn "DNS mismatch: $DOMAIN → $domain_ip (server IP: $server_ip)"
        log_warn "SSL certificate will fail until DNS is corrected"
    fi
}

# Show summary
show_summary() {
    echo ""
    log_info "=== Configuration Summary ==="
    log_info "Domain: $DOMAIN"
    log_info "Environment: $ENVIRONMENT"
    log_info "Odoo Port: $ODOO_PORT"
    log_info "Upstream: $ODOO_UPSTREAM"
    log_info ""
    log_info "Your Odoo instance will be available at:"
    log_info "  https://$DOMAIN"
    echo ""
    log_info "SSL certificates will be automatically obtained from Let's Encrypt"
    log_warn "Make sure port 80 and 443 are accessible from the internet"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=========================================="
    log_info "Caddy Reverse Proxy Configuration"
    log_info "=========================================="
    echo ""

    check_root
    parse_args "$@"
    check_caddy_installed
    create_backup_dir

    if [[ "$REMOVE_CONFIG" == true ]]; then
        backup_caddyfile
        remove_caddy_config
        validate_config
        reload_caddy
        show_status
        exit 0
    fi

    # Show configuration
    log_info "Configuration:"
    log_info "  Domain: $DOMAIN"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Odoo Port: $ODOO_PORT"
    log_info "  Upstream: $ODOO_UPSTREAM"
    echo ""

    check_dns

    read -p "Continue with Caddy configuration? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi

    backup_caddyfile
    add_caddy_config
    validate_config
    reload_caddy
    show_status
    show_summary

    log_info "Next steps:"
    log_info "1. Wait for SSL certificate issuance (check logs: journalctl -u caddy -f)"
    log_info "2. Access Odoo at: https://$DOMAIN"
    log_info "3. Update odoo.conf: proxy_mode = True"
}

main "$@"
