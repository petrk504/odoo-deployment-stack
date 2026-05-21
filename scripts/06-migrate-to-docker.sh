#!/bin/bash
################################################################################
# Bare-Metal to Docker Migration Script
# Purpose: Migrate existing bare-metal Odoo installation to Docker
#
# This script handles the complete migration process:
# 1. Backup bare-metal database and filestore
# 2. Start Docker containers
# 3. Restore data to Docker
# 4. Validate migration
# 5. Keep bare-metal as fallback
#
# Author: Petr
# Version: 1.0
# Last Updated: March 2026
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION
################################################################################

# Environment
ENVIRONMENT=${ENVIRONMENT:-test}

# Bare-metal configuration
BARE_METAL_DB_USER=${BARE_METAL_DB_USER:-postgres}
BARE_METAL_DB_NAME=${BARE_METAL_DB_NAME:-vina}
BARE_METAL_DB_PROD=${BARE_METAL_DB_NAME:-vina-prod-01}
BARE_METAL_FILESTORE_TEST=${BARE_METAL_FILESTORE_TEST:-/opt/odoo18/odoo/.local/share/Odoo/filestore}
BARE_METAL_FILESTORE_PROD=${BARE_METAL_FILESTORE_PROD:-/opt/odoo-prod/odoo/.local/share/Odoo/filestore}
BARE_METAL_SERVICE_TEST=${BARE_METAL_SERVICE_TEST:-odoo18}
BARE_METAL_SERVICE_PROD=${BARE_METAL_SERVICE_PROD:-odoo-prod}

# Docker configuration
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-odoo}
DOCKER_DIR="${DOCKER_DIR:-$(pwd)/docker/${ENVIRONMENT}}"
DOCKER_DB_USER=${DOCKER_DB_USER:-odoo}
DOCKER_DB_NAME=${DOCKER_DB_NAME:-${ENVIRONMENT}}

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backups/migration}"
MIGRATION_LOG="${BACKUP_DIR}/migration_$(date +%Y%m%d_%H%M%S).log"

# Migration options
STOP_BARE_METAL=${STOP_BARE_METAL:-true}
VALIDATE_AFTER_MIGRATE=${VALIDATE_AFTER_MIGRATE:-true}
KEEP_BACKUP=${KEEP_BACKUP:-true}
ROLLBACK_ON_ERROR=${ROLLBACK_ON_ERROR:-true}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

################################################################################
# LOGGING FUNCTIONS
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$MIGRATION_LOG"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$MIGRATION_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$MIGRATION_LOG" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1" | tee -a "$MIGRATION_LOG"
}

log_migration() {
    echo -e "${MAGENTA}[MIGRATE]${NC} $1" | tee -a "$MIGRATION_LOG"
}

################################################################################
# ERROR HANDLING
################################################################################

handle_error() {
    log_error "Migration failed at line $1"

    if [[ "$ROLLBACK_ON_ERROR" == true ]]; then
        log_migration "Rollback available: Bare-metal is still intact"
        log_migration "Docker containers can be stopped: cd $DOCKER_DIR && docker compose down"
    fi

    exit 1
}

trap 'handle_error $LINENO' ERR

################################################################################
# FUNCTIONS
################################################################################

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Migrate bare-metal Odoo installation to Docker containers.

OPTIONS:
    -e, --environment ENV       Environment: test, prod [default: test]
    -s, --source-db DB          Source database name [auto-detected]
    -d, --docker-dir DIR        Docker compose directory [default: ./docker/ENV]
    --keep-bare-metal-running   Keep bare-metal service running during migration
    --no-validate               Skip post-migration validation
    --no-rollback               Don't offer rollback on error
    --no-backup                 Skip backup (use existing)
    -h, --help                  Show this help message

SAFETY FEATURES:
    - Bare-metal remains intact (fallback)
    - Complete backup before migration
    - Validation after migration
    - Detailed logging
    - Rollback capability

EXAMPLES:
    # Migrate test environment
    sudo $0 --environment test

    # Migrate production with custom backup directory
    sudo $0 --environment prod

    # Keep bare-metal running during migration (downtime-free)
    sudo $0 --environment test --keep-bare-metal-running

REQUIREMENTS:
    - Bare-metal Odoo service must be running
    - Docker Compose stack must be configured
    - Sufficient disk space for backups
    - Root or sudo access

PROCESS:
    1. Pre-migration checks (disk space, services, etc.)
    2. Backup bare-metal database and filestore
    3. Stop bare-metal service (optional)
    4. Start Docker containers
    5. Restore data to Docker
    6. Validate migration
    7. Update Caddy proxy (point to Docker port)
    8. Post-migration validation

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
            -s|--source-db)
                BARE_METAL_DB_NAME="$2"
                shift 2
                ;;
            -d|--docker-dir)
                DOCKER_DIR="$2"
                shift 2
                ;;
            --keep-bare-metal-running)
                STOP_BARE_METAL=false
                shift
                ;;
            --no-validate)
                VALIDATE_AFTER_MIGRATE=false
                shift
                ;;
            --no-rollback)
                ROLLBACK_ON_ERROR=false
                shift
                ;;
            --no-backup)
                KEEP_BACKUP=false
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

    # Auto-detect database name based on environment
    if [[ -z "${BARE_METAL_DB_NAME:-}" ]]; then
        if [[ "$ENVIRONMENT" == "prod" ]]; then
            BARE_METAL_DB_NAME="$BARE_METAL_DB_PROD"
        else
            BARE_METAL_DB_NAME="$BARE_METAL_DB_NAME"
        fi
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        log_info "Migration requires access to:"
        log_info "  - PostgreSQL database"
        log_info "  - Filestore directories"
        log_info "  - Systemd services"
        exit 1
    fi
}

# Create backup directory
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log_info "Created backup directory: $BACKUP_DIR"
    fi
}

# Pre-migration checks
pre_migration_checks() {
    log_step "Running pre-migration checks..."

    # Check disk space
    local available_space_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    local required_space_gb=5  # Minimum 5GB free

    if [[ $available_space_gb -lt $required_space_gb ]]; then
        log_error "Insufficient disk space. Required: ${required_space_gb}GB, Available: ${available_space_gb}GB"
        exit 1
    fi

    log_info "Disk space check passed: ${available_space_gb}GB available"

    # Check Docker Compose configuration
    if [[ ! -f "${DOCKER_DIR}/docker-compose.yml" ]]; then
        log_error "Docker Compose configuration not found: ${DOCKER_DIR}/docker-compose.yml"
        log_info "Generate configuration first: ./scripts/02-generate-odoo-stack.sh --environment $ENVIRONMENT"
        exit 1
    fi

    log_info "Docker Compose configuration found"

    # Check bare-metal service
    local bare_metal_service="$BARE_METAL_SERVICE_TEST"
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        bare_metal_service="$BARE_METAL_SERVICE_PROD"
    fi

    if systemctl is-active --quiet "$bare_metal_service"; then
        log_info "Bare-metal service is running: $bare_metal_service"
    else
        log_warn "Bare-metal service is not running: $bare_metal_service"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Migration aborted"
            exit 0
        fi
    fi

    # Check database exists
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$BARE_METAL_DB_NAME"; then
        log_info "Database exists: $BARE_METAL_DB_NAME"
    else
        log_error "Database not found: $BARE_METAL_DB_NAME"
        exit 1
    fi

    # Check filestore exists
    local filestore_path="$BARE_METAL_FILESTORE_TEST/$BARE_METAL_DB_NAME"
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        filestore_path="$BARE_METAL_FILESTORE_PROD/$BARE_METAL_DB_NAME"
    fi

    if [[ -d "$filestore_path" ]]; then
        local filestore_size=$(du -sh "$filestore_path" | cut -f1)
        log_info "Filestore exists: $filestore_path ($filestore_size)"
    else
        log_warn "Filestore not found: $filestore_path"
    fi

    log_info "Pre-migration checks passed"
}

# Backup bare-metal data
backup_bare_metal() {
    log_step "Backing up bare-metal data..."

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local db_backup="${BACKUP_DIR}/${BARE_METAL_DB_NAME}_bare_metal_${timestamp}.sql"
    local filestore_backup="${BACKUP_DIR}/${BARE_METAL_DB_NAME}_filestore_bare_metal_${timestamp}.tar.gz"

    # Backup database
    log_info "Backing up database: $BARE_METAL_DB_NAME"
    sudo -u postgres pg_dump "$BARE_METAL_DB_NAME" > "$db_backup"

    local db_size=$(du -h "$db_backup" | cut -f1)
    log_info "Database backup created: $db_backup ($db_size)"

    # Backup filestore
    local filestore_path="$BARE_METAL_FILESTORE_TEST"
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        filestore_path="$BARE_METAL_FILESTORE_PROD"
    fi

    if [[ -d "$filestore_path" ]]; then
        log_info "Backing up filestore..."
        tar czf "$filestore_backup" -C "$filestore_path" .

        local fs_size=$(du -h "$filestore_backup" | cut -f1)
        log_info "Filestore backup created: $filestore_backup ($fs_size)"
    fi

    log_info "Bare-metal backup complete"
}

# Stop bare-metal service
stop_bare_metal() {
    if [[ "$STOP_BARE_METAL" == false ]]; then
        log_info "Keeping bare-metal service running (--keep-bare-metal-running)"
        return
    fi

    local bare_metal_service="$BARE_METAL_SERVICE_TEST"
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        bare_metal_service="$BARE_METAL_SERVICE_PROD"
    fi

    log_step "Stopping bare-metal service: $bare_metal_service"

    systemctl stop "$bare_metal_service"

    # Wait for service to stop
    sleep 3

    if systemctl is-active --quiet "$bare_metal_service"; then
        log_error "Failed to stop $bare_metal_service"
        exit 1
    fi

    log_info "Bare-metal service stopped"
}

# Start Docker containers
start_docker() {
    log_step "Starting Docker containers..."

    cd "$DOCKER_DIR"

    # Check if .env file exists
    if [[ ! -f ".env" ]]; then
        log_error ".env file not found in $DOCKER_DIR"
        log_info "Create .env from .env.example first"
        exit 1
    fi

    # Start containers
    docker compose up -d

    # Wait for database to be ready
    log_info "Waiting for database to be ready..."
    local max_wait=60
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if docker compose exec -T db pg_isready -U "$DOCKER_DB_USER" &>/dev/null; then
            log_info "Database is ready"
            break
        fi
        sleep 2
        ((waited += 2))
    done

    if [[ $waited -ge $max_wait ]]; then
        log_error "Database failed to start"
        exit 1
    fi

    log_info "Docker containers started"
}

# Restore data to Docker
restore_data_to_docker() {
    log_step "Restoring data to Docker..."

    cd "$DOCKER_DIR"

    # Find latest backup
    local db_backup=$(ls -t ${BACKUP_DIR}/${BARE_METAL_DB_NAME}_bare_metal_*.sql 2>/dev/null | head -1)
    local filestore_backup=$(ls -t ${BACKUP_DIR}/${BARE_METAL_DB_NAME}_filestore_bare_metal_*.tar.gz 2>/dev/null | head -1)

    if [[ -z "$db_backup" ]]; then
        log_error "Database backup not found in $BACKUP_DIR"
        exit 1
    fi

    # Restore database
    log_info "Restoring database to Docker..."
    docker compose exec -T db psql -U "$DOCKER_DB_USER" "$DOCKER_DB_NAME" < "$db_backup"
    log_info "Database restored"

    # Restore filestore
    if [[ -n "$filestore_backup" ]]; then
        log_info "Restoring filestore to Docker..."

        local volume_name="${COMPOSE_PROJECT_NAME}-${ENVIRONMENT}-filestore"

        # Clear existing filestore
        docker run --rm \
            -v "${volume_name}:/data" \
            alpine sh -c "rm -rf /data/*"

        # Restore filestore
        docker run --rm \
            -v "${volume_name}:/data" \
            -v "${BACKUP_DIR}:/backup" \
            alpine tar xzf "/backup/$(basename "$filestore_backup")" -C /data

        log_info "Filestore restored"
    fi

    log_info "Data restoration complete"
}

# Validate migration
validate_migration() {
    if [[ "$VALIDATE_AFTER_MIGRATE" == false ]]; then
        log_info "Validation skipped (--no-validate)"
        return
    fi

    log_step "Validating migration..."

    cd "$DOCKER_DIR"

    # Check containers are running
    if docker compose ps | grep -q "Up"; then
        log_info "Docker containers are running"
    else
        log_error "Some containers are not running"
        docker compose ps
        exit 1
    fi

    # Check database has data
    local table_count=$(docker compose exec -T db psql -U "$DOCKER_DB_USER" "$DOCKER_DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs || echo "0")

    if [[ $table_count -gt 0 ]]; then
        log_info "Database contains $table_count tables"
    else
        log_error "Database appears to be empty"
        exit 1
    fi

    # Check Odoo is responding
    local odoop_port=$ODOO_PORT
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        odoop_port=8070
    else
        odoop_port=8069
    fi

    sleep 5  # Give Odoo time to start

    if command -v curl &> /dev/null; then
        if curl -s "http://localhost:${odoop_port}" | head -1 | grep -q "DOCTYPE\|xml"; then
            log_info "Odoo is responding on port ${odoop_port}"
        else
            log_warn "Odoo may not be fully ready yet"
        fi
    fi

    log_info "Migration validation passed"
}

# Show migration summary
show_migration_summary() {
    echo ""
    log_migration "=========================================="
    log_migration "   Migration Complete"
    log_migration "=========================================="
    echo ""

    log_migration "Environment: $ENVIRONMENT"
    log_migration "Source Database: $BARE_METAL_DB_NAME"
    log_migration "Target Database: $DOCKER_DB_NAME"
    log_migration "Docker Directory: $DOCKER_DIR"
    log_migration "Migration Log: $MIGRATION_LOG"
    echo ""

    log_migration "Bare-Metal Status: Stopped (can be restarted)"
    log_migration "Docker Status: Running"
    echo ""

    log_info "Next steps:"
    log_info "  1. Update Caddy reverse proxy:"
    log_info "     sudo ./scripts/03-setup-caddy.sh --domain YOUR_DOMAIN --port $ODOO_PORT"
    echo ""
    log_info "  2. Verify Odoo is accessible:"
    log_info "     Open https://YOUR_DOMAIN in browser"
    echo ""
    log_info "  3. Test critical functionality:"
    log_info "     - Create/save records"
    log_info "     - Upload attachments"
    log_info "     - Run reports"
    echo ""
    log_info "  4. Monitor Docker logs:"
    log_info "     cd $DOCKER_DIR && docker compose logs -f"
    echo ""

    if [[ "$ENVIRONMENT" == "test" ]]; then
        log_info "  5. After 1-2 weeks of validation, repeat for production"
    fi

    log_warn "Keep bare-metal as fallback until Docker is fully validated!"
    log_warn "To roll back: systemctl start $BARE_METAL_SERVICE_TEST && cd $DOCKER_DIR && docker compose down"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_migration "=========================================="
    log_migration "Bare-Metal to Docker Migration"
    log_migration "=========================================="
    echo ""

    parse_args "$@"
    check_root
    create_backup_dir

    log_migration "Migration Configuration:"
    log_migration "  Environment: $ENVIRONMENT"
    log_migration "  Source Database: $BARE_METAL_DB_NAME"
    log_migration "  Target Database: $DOCKER_DB_NAME"
    log_migration "  Docker Directory: $DOCKER_DIR"
    log_migration "  Stop Bare-Metal: $STOP_BARE_METAL"
    log_migration "  Validate: $VALIDATE_AFTER_MIGRATE"
    echo ""

    log_migration "IMPORTANT: This migration is NON-DESTRUCTIVE to bare-metal"
    log_migration "Bare-metal installation will remain intact as fallback"
    echo ""

    read -p "Continue with migration? (yes/no): " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        log_migration "Migration aborted"
        exit 0
    fi

    pre_migration_checks
    backup_bare_metal
    stop_bare_metal
    start_docker
    restore_data_to_docker
    validate_migration
    show_migration_summary

    log_migration "Migration completed successfully!"
}

main "$@"
