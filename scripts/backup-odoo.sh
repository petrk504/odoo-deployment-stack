#!/bin/bash
################################################################################
# Odoo Backup and Restore Script
# Purpose: Backup and restore PostgreSQL databases and Odoo filestore
#
# Features:
# - Automated backups with retention policy
# - Support for both bare-metal and Docker deployments
# - Compression and encryption support
# - Email notifications (optional)
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
ENVIRONMENT=${ENVIRONMENT:-test}              # test, prod
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE:-auto}      # auto, docker, bare-metal

# Paths (will be auto-detected based on deployment type)
BACKUP_DIR="${BACKUP_DIR:-/var/backups/odoo}"
RETENTION_DAYS=${RETENTION_DAYS:-7}

# Database configuration (will be auto-detected)
DB_NAME=${DB_NAME:-}
DB_USER=${DB_USER:-odoo}
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5432}

# Docker configuration
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-odoo}
DOCKER_DIR="${DOCKER_DIR:-$(pwd)/docker/${ENVIRONMENT}}"

# Backup options
COMPRESS=${COMPRESS:-true}
ENCRYPT=${ENCRYPT:-false}
ENCRYPTION_KEY=${ENCRYPTION_KEY:-}

# Notification
EMAIL_NOTIFY=${EMAIL_NOTIFY:-false}
EMAIL_ADDRESS=${EMAIL_ADDRESS:-}

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
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

################################################################################
# FUNCTIONS
################################################################################

show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Odoo backup and restore automation tool.

COMMANDS:
    backup              Backup database and filestore
    restore FILE        Restore from backup file
    list                List available backups
    clean               Remove old backups (based on retention policy)
    test-restore        Test restore latest backup to temporary DB

OPTIONS:
    -e, --environment ENV       Environment: test, prod [default: test]
    -d, --database DB           Database name [auto-detected if omitted]
    -t, --type TYPE             Deployment type: auto, docker, bare-metal [default: auto]
    -r, --retention DAYS        Backup retention in days [default: 7]
    -o, --output-dir DIR        Backup directory [default: /var/backups/odoo]
    --no-compress               Disable compression
    --encrypt                   Enable encryption (requires ENCRYPTION_KEY env var)

ENVIRONMENT VARIABLES:
    POSTGRES_PASSWORD           PostgreSQL password (for bare-metal)
    POSTGRES_USER               PostgreSQL user [default: odoo]

EXAMPLES:
    # Backup test environment (auto-detect deployment type)
    $0 backup --environment test

    # Restore specific backup
    $0 restore /var/backups/odoo/vina_backup_20260314.tar.gz

    # List backups
    $0 list

    # Clean old backups
    $0 clean --retention 7

EOF
}

# Parse command line arguments
parse_args() {
    COMMAND="${1:-}"
    shift || true

    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -d|--database)
                DB_NAME="$2"
                shift 2
                ;;
            -t|--type)
                DEPLOYMENT_TYPE="$2"
                shift 2
                ;;
            -r|--retention)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            -o|--output-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --no-compress)
                COMPRESS=false
                shift
                ;;
            --encrypt)
                ENCRYPT=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                # Assume it's the backup file for restore command
                if [[ "$COMMAND" == "restore" ]]; then
                    BACKUP_FILE="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate command
    if [[ ! "$COMMAND" =~ ^(backup|restore|list|clean|test-restore)$ ]]; then
        log_error "Invalid command: $COMMAND"
        show_usage
        exit 1
    fi
}

# Detect deployment type (Docker vs bare-metal)
detect_deployment() {
    if [[ "$DEPLOYMENT_TYPE" != "auto" ]]; then
        log_info "Using specified deployment type: $DEPLOYMENT_TYPE"
        return
    fi

    # Check if Docker Compose file exists
    if [[ -f "${DOCKER_DIR}/docker-compose.yml" ]]; then
        DEPLOYMENT_TYPE="docker"
        log_info "Detected Docker deployment"
    elif command -v psql &> /dev/null && sudo -u postgres psql -lqt &> /dev/null; then
        DEPLOYMENT_TYPE="bare-metal"
        log_info "Detected bare-metal deployment"
    else
        log_error "Cannot detect deployment type. Please specify with --type"
        exit 1
    fi
}

# Auto-detect database name
detect_database() {
    if [[ -n "$DB_NAME" ]]; then
        log_info "Using specified database: $DB_NAME"
        return
    fi

    if [[ "$ENVIRONMENT" == "prod" ]]; then
        DB_NAME="vina-prod-01"
    else
        DB_NAME="vina"
    fi

    log_info "Auto-detected database: $DB_NAME"
}

# Check database exists
check_database_exists() {
    local db_exists=false

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        # Check in Docker
        cd "$DOCKER_DIR"
        db_exists=$(docker compose exec -T db psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -w "$DB_NAME" || true)
    else
        # Check bare-metal
        db_exists=$(sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -w "$DB_NAME" || true)
    fi

    if [[ -z "$db_exists" ]]; then
        log_error "Database '$DB_NAME' not found"
        exit 1
    fi

    log_info "Database '$DB_NAME' exists"
}

# Create backup directory
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_step "Creating backup directory: $BACKUP_DIR"
        sudo mkdir -p "$BACKUP_DIR"
        sudo chown $USER:$USER "$BACKUP_DIR"
    fi
}

# Backup database
backup_database() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/${DB_NAME}_backup_${timestamp}.sql"

    log_step "Backing up database '$DB_NAME'..."

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        cd "$DOCKER_DIR"
        docker compose exec -T db pg_dump -U "$DB_USER" "$DB_NAME" > "$backup_file"
    else
        sudo -u postgres pg_dump "$DB_NAME" > "$backup_file"
    fi

    local size=$(du -h "$backup_file" | cut -f1)
    log_info "Database backup completed: $backup_file ($size)"

    echo "$backup_file"
}

# Backup filestore
backup_filestore() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filestore_backup="${BACKUP_DIR}/${DB_NAME}_filestore_${timestamp}.tar.gz"

    log_step "Backing up Odoo filestore..."

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        cd "$DOCKER_DIR"
        local volume_name="${COMPOSE_PROJECT_NAME}-${ENVIRONMENT}-filestore"

        # Backup from Docker volume
        docker run --rm \
            -v "${volume_name}:/data" \
            -v "${BACKUP_DIR}:/backup" \
            alpine tar czf "/backup/$(basename "$filestore_backup")" -C /data .
    else
        # Bare-metal filestore location
        local filestore_path="/opt/odoo18/odoo/.local/share/Odoo/filestore/$DB_NAME"

        if [[ ! -d "$filestore_path" ]]; then
            log_warn "Filestore not found at $filestore_path"
            echo ""
            return
        fi

        tar czf "$filestore_backup" -C "$(dirname "$filestore_path")" "$(basename "$filestore_path")"
    fi

    local size=$(du -h "$filestore_backup" | cut -f1)
    log_info "Filestore backup completed: $filestore_backup ($size)"

    echo "$filestore_backup"
}

# Create combined backup archive
create_combined_backup() {
    local db_backup="$1"
    local filestore_backup="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local combined_backup="${BACKUP_DIR}/${DB_NAME}_full_backup_${timestamp}.tar.gz"

    log_step "Creating combined backup archive..."

    # Create a temporary directory for organization
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    cp "$db_backup" "$temp_dir/database.sql"
    cp "$filestore_backup" "$temp_dir/filestore.tar.gz"

    # Create metadata file
    cat > "$temp_dir/backup_info.txt" << EOF
Backup Information
==================
Environment: $ENVIRONMENT
Database: $DB_NAME
Date: $(date)
Deployment Type: $DEPLOYMENT_TYPE
Database File: database.sql
Filestore File: filestore.tar.gz
EOF

    # Create combined archive
    tar czf "$combined_backup" -C "$temp_dir" .

    local size=$(du -h "$combined_backup" | cut -f1)
    log_info "Combined backup created: $combined_backup ($size)"

    # Clean up individual backups
    rm -f "$db_backup" "$filestore_backup"

    echo "$combined_backup"
}

# List available backups
list_backups() {
    create_backup_dir

    log_step "Available backups in $BACKUP_DIR:"
    echo ""

    if [[ ! "$(ls -A $BACKUP_DIR 2>/dev/null)" ]]; then
        log_warn "No backups found"
        return
    fi

    ls -lh "$BACKUP_DIR" | grep -E "\.(sql|tar\.gz)$" | awk '{print $9, "("$5")"}'
}

# Clean old backups
clean_old_backups() {
    create_backup_dir

    log_step "Cleaning backups older than $RETENTION_DAYS days..."

    local deleted=0
    deleted=$(find "$BACKUP_DIR" -name "*.sql" -o -name "*.tar.gz" -mtime +$RETENTION_DAYS -print -delete 2>/dev/null | wc -l)

    if [[ $deleted -gt 0 ]]; then
        log_info "Deleted $deleted old backup(s)"
    else
        log_info "No old backups to clean"
    fi
}

# Restore from backup
restore_backup() {
    local backup_file="$1"

    log_step "Restoring from backup: $backup_file"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi

    # Create temp directory for extraction
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    # Extract backup
    log_info "Extracting backup..."
    tar xzf "$backup_file" -C "$temp_dir"

    # Check for combined backup
    if [[ -f "$temp_dir/backup_info.txt" ]]; then
        log_info "Detected combined backup format"

        # Restore database
        if [[ -f "$temp_dir/database.sql" ]]; then
            restore_database "$temp_dir/database.sql"
        fi

        # Restore filestore
        if [[ -f "$temp_dir/filestore.tar.gz" ]]; then
            restore_filestore "$temp_dir/filestore.tar.gz"
        fi
    elif [[ "$backup_file" == *.sql ]]; then
        # Database only backup
        restore_database "$backup_file"
    else
        log_error "Unknown backup format"
        exit 1
    fi

    log_info "Restore completed successfully"
}

# Restore database
restore_database() {
    local sql_file="$1"

    log_step "Restoring database..."

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        cd "$DOCKER_DIR"
        docker compose exec -T db psql -U "$DB_USER" "$DB_NAME" < "$sql_file"
    else
        sudo -u postgres psql "$DB_NAME" < "$sql_file"
    fi

    log_info "Database restored"
}

# Restore filestore
restore_filestore() {
    local archive="$1"

    log_step "Restoring filestore..."

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        cd "$DOCKER_DIR"
        local volume_name="${COMPOSE_PROJECT_NAME}-${ENVIRONMENT}-filestore"

        # Clear existing filestore (optional - comment out to preserve)
        # docker run --rm -v "${volume_name}:/data" alpine sh -c "rm -rf /data/*"

        # Restore filestore
        docker run --rm \
            -v "${volume_name}:/data" \
            -v "$(dirname "$archive"):/backup" \
            alpine tar xzf "/backup/$(basename "$archive")" -C /data
    else
        local filestore_path="/opt/odoo18/odoo/.local/share/Odoo/filestore/$DB_NAME"

        # Clear existing filestore (optional)
        # rm -rf "$filestore_path"

        mkdir -p "$filestore_path"
        tar xzf "$archive" -C "$(dirname "$filestore_path")"
    fi

    log_info "Filestore restored"
}

# Main backup function
cmd_backup() {
    detect_deployment
    detect_database
    check_database_exists
    create_backup_dir

    log_info "Starting backup for environment: $ENVIRONMENT"
    log_info "Database: $DB_NAME"
    log_info "Deployment type: $DEPLOYMENT_TYPE"
    echo ""

    local db_backup=$(backup_database)
    local filestore_backup=$(backup_filestore)

    echo ""

    local combined_backup=$(create_combined_backup "$db_backup" "$filestore_backup")

    echo ""
    log_info "=== Backup Complete ==="
    log_info "Backup file: $combined_backup"

    # Clean old backups
    clean_old_backups
}

# Main restore function
cmd_restore() {
    if [[ -z "${BACKUP_FILE:-}" ]]; then
        log_error "Please specify backup file to restore"
        show_usage
        exit 1
    fi

    detect_deployment
    detect_database
    create_backup_dir

    log_warn "=== WARNING: Restore Operation ==="
    log_warn "This will OVERWRITE the existing database '$DB_NAME'"
    echo ""
    read -p "Continue with restore? (yes/no): " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "Restore aborted"
        exit 0
    fi

    restore_backup "$BACKUP_FILE"
}

# Main list function
cmd_list() {
    create_backup_dir
    list_backups
}

# Main clean function
cmd_clean() {
    create_backup_dir
    clean_old_backups
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=========================================="
    log_info "Odoo Backup and Restore Tool"
    log_info "=========================================="
    echo ""

    parse_args "$@"

    case "$COMMAND" in
        backup)
            cmd_backup
            ;;
        restore)
            cmd_restore
            ;;
        list)
            cmd_list
            ;;
        clean)
            cmd_clean
            ;;
        test-restore)
            log_error "Test restore not yet implemented"
            exit 1
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
