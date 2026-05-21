#!/bin/bash
################################################################################
# Odoo Deployment Script
# Purpose: Automate git-based deployment workflow
#
# This script implements the documented deployment flow:
#   Local (git push) → GitHub → Server (git pull) → Odoo (restart)
#
# Supports both Docker and bare-metal deployments.
#
# Author: Petr
# Version: 1.0
# Last Updated: March 2026
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION
################################################################################

# Deployment configuration
ENVIRONMENT=${ENVIRONMENT:-test}
BRANCH=${BRANCH:-main}
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE:-auto}  # auto, docker, bare-metal

# Git configuration
GIT_REMOTE=${GIT_REMOTE:-origin}
REMOTE_REPO=${REMOTE_REPO:-""}  # Auto-detected if not specified
LOCAL_REPO_PATH=${LOCAL_REPO_PATH:-""}

# Docker configuration
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-odoo}
DOCKER_DIR="${DOCKER_DIR:-$(pwd)/docker/${ENVIRONMENT}}"

# Bare-metal configuration
ODOO_SERVICE_TEST=${ODOO_SERVICE_TEST:-odoo18}
ODOO_SERVICE_PROD=${ODOO_SERVICE_PROD:-odoo-prod}
ODOO_USER_TEST=${ODOO_USER_TEST:-odoo18}
ODOO_USER_PROD=${ODOO_USER_PROD:-odoo-prod}
CUSTOM_ADDONS_PATH_TEST=${CUSTOM_ADDONS_PATH_TEST:-/opt/odoo18/odoo18-custom-addons}
CUSTOM_ADDONS_PATH_PROD=${CUSTOM_ADDONS_PATH_PROD:-/opt/odoo-prod/custom-addons}

# Deployment options
AUTO_RESTART=${AUTO_RESTART:-true}
BACKUP_BEFORE_DEPLOY=${BACKUP_BEFORE_DEPLOY:-true}
DRY_RUN=${DRY_RUN:-false}
SKIP_TESTS=${SKIP_TESTS:-false}

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

log_deploy() {
    echo -e "${MAGENTA}[DEPLOY]${NC} $1"
}

################################################################################
# ERROR HANDLING
################################################################################

handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Rollback may be required"

    if [[ "$BACKUP_BEFORE_DEPLOY" == true ]]; then
        log_warn "Backup is available for recovery"
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

Automate Odoo deployment workflow with git pull and service restart.

OPTIONS:
    -e, --environment ENV       Environment: test, prod [default: test]
    -b, --branch BRANCH         Git branch to deploy [default: main]
    -t, --type TYPE             Deployment type: auto, docker, bare-metal [default: auto]
    -p, --path PATH             Local repository path [default: auto-detect]
    -r, --remote REMOTE         Git remote [default: origin]
    --no-restart                Skip automatic restart
    --no-backup                 Skip backup before deployment
    --dry-run                   Show what would be done without executing
    --skip-tests                Skip pre-deployment checks
    -h, --help                  Show this help message

EXAMPLES:
    # Deploy to test environment
    $0 --environment test

    # Deploy specific branch to production
    $0 --environment prod --branch feature/new-module

    # Dry run to see what would change
    $0 --environment test --dry-run

    # Deploy without automatic restart
    $0 --environment test --no-restart

WORKFLOW:
    1. Pre-deployment checks (git status, uncommitted changes)
    2. Optional backup (database + filestore)
    3. Pull latest changes from remote
    4. Show commit diff
    5. Restart Odoo service (Docker or bare-metal)
    6. Post-deployment health check
    7. Show deployment summary

REQUIREMENTS:
    - Git repository must be initialized
    - SSH access to server (if running remotely)
    - Backup script (if backup enabled)

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
            -b|--branch)
                BRANCH="$2"
                shift 2
                ;;
            -t|--type)
                DEPLOYMENT_TYPE="$2"
                shift 2
                ;;
            -p|--path)
                LOCAL_REPO_PATH="$2"
                shift 2
                ;;
            -r|--remote)
                GIT_REMOTE="$2"
                shift 2
                ;;
            --no-restart)
                AUTO_RESTART=false
                shift
                ;;
            --no-backup)
                BACKUP_BEFORE_DEPLOY=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
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

# Detect deployment type
detect_deployment_type() {
    if [[ "$DEPLOYMENT_TYPE" != "auto" ]]; then
        log_info "Using specified deployment type: $DEPLOYMENT_TYPE"
        return
    fi

    # Check if Docker Compose file exists
    if [[ -f "${DOCKER_DIR}/docker-compose.yml" ]]; then
        DEPLOYMENT_TYPE="docker"
        log_info "Detected Docker deployment"
    elif systemctl is-active --quiet "${ODOO_SERVICE_TEST}" 2>/dev/null || \
         systemctl is-active --quiet "${ODOO_SERVICE_PROD}" 2>/dev/null; then
        DEPLOYMENT_TYPE="bare-metal"
        log_info "Detected bare-metal deployment"
    else
        log_error "Cannot detect deployment type"
        log_error "Docker Compose not found at: ${DOCKER_DIR}"
        log_error "Systemd services not found: ${ODOO_SERVICE_TEST}, ${ODOO_SERVICE_PROD}"
        exit 1
    fi
}

# Detect repository path
detect_repo_path() {
    if [[ -n "$LOCAL_REPO_PATH" ]]; then
        log_info "Using specified repository path: $LOCAL_REPO_PATH"
        return
    fi

    # Try to find .git directory
    local current_dir="$(pwd)"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            LOCAL_REPO_PATH="$current_dir"
            log_info "Detected repository path: $LOCAL_REPO_PATH"
            return
        fi
        current_dir="$(dirname "$current_dir")"
    done

    log_error "Cannot detect repository path. Please specify with --path"
    exit 1
}

# Pre-deployment checks
pre_deployment_checks() {
    log_step "Running pre-deployment checks..."

    cd "$LOCAL_REPO_PATH"

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository: $LOCAL_REPO_PATH"
        exit 1
    fi

    # Check for uncommitted changes
    if [[ "$SKIP_TESTS" == false ]]; then
        if ! git diff-index --quiet HEAD --; then
            log_error "You have uncommitted changes"
            log_info "Commit or stash changes before deploying"
            git status --short
            exit 1
        fi

        # Check for untracked files
        local untracked=$(git ls-files --others --exclude-standard | wc -l)
        if [[ $untracked -gt 0 ]]; then
            log_warn "You have $untracked untracked file(s)"
            git ls-files --others --exclude-standard
            read -p "Continue anyway? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Deployment aborted"
                exit 0
            fi
        fi
    fi

    # Check current branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    log_info "Current branch: $current_branch"

    # Get remote URL
    REMOTE_REPO=$(git remote get-url "$GIT_REMOTE" 2>/dev/null || echo "")
    if [[ -n "$REMOTE_REPO" ]]; then
        log_info "Remote: $REMOTE_REPO"
    fi

    log_info "Pre-deployment checks passed"
}

# Create backup
create_backup() {
    if [[ "$BACKUP_BEFORE_DEPLOY" == false ]]; then
        log_info "Backup skipped (--no-backup)"
        return
    fi

    log_step "Creating backup before deployment..."

    local backup_script="${LOCAL_REPO_PATH}/scripts/backup-odoo.sh"

    if [[ ! -f "$backup_script" ]]; then
        log_warn "Backup script not found: $backup_script"
        log_warn "Skipping backup"
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create backup"
        return
    fi

    # Run backup script
    if bash "$backup_script" backup --environment "$ENVIRONMENT"; then
        log_info "Backup created successfully"
    else
        log_error "Backup failed. Aborting deployment."
        exit 1
    fi
}

# Pull latest changes
pull_changes() {
    log_step "Pulling latest changes from $GIT_REMOTE/$BRANCH..."

    cd "$LOCAL_REPO_PATH"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would pull from $GIT_REMOTE/$BRANCH"
        return
    fi

    # Fetch from remote
    git fetch "$GIT_REMOTE"

    # Show commits that will be pulled
    local local_head=$(git rev-parse HEAD)
    local remote_head=$(git rev-parse "$GIT_REMOTE/$BRANCH")

    if [[ "$local_head" == "$remote_head" ]]; then
        log_info "Already up to date"
        return
    fi

    log_info "Changes to be pulled:"
    git log --oneline "$local_head..$remote_head" || true
    echo ""

    # Pull changes
    git pull "$GIT_REMOTE" "$BRANCH"

    log_info "Changes pulled successfully"
}

# Show deployment summary
show_deployment_summary() {
    cd "$LOCAL_REPO_PATH"

    log_step "Deployment Summary"
    echo ""

    # Show recent commits
    log_info "Recent commits:"
    git log --oneline -5
    echo ""

    # Show changed files (if any)
    local changed_files=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
    if [[ -n "$changed_files" ]]; then
        log_info "Files changed in latest commit:"
        echo "$changed_files"
        echo ""
    fi
}

# Get service details for bare-metal
get_bare_metal_service() {
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        echo "$ODOO_SERVICE_PROD"
    else
        echo "$ODOO_SERVICE_TEST"
    fi
}

# Restart Docker service
restart_docker() {
    log_step "Restarting Docker Odoo container..."

    cd "$DOCKER_DIR"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would restart Odoo container"
        return
    fi

    # Restart only Odoo container (database stays up)
    docker compose restart odoo

    # Wait for container to be healthy
    log_info "Waiting for Odoo to be ready..."
    local max_wait=30
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if docker compose ps odoo | grep -q "healthy\|running"; then
            log_info "Odoo is ready"
            break
        fi
        sleep 2
        ((waited += 2))
    done

    if [[ $waited -ge $max_wait ]]; then
        log_warn "Odoo may not be fully started yet"
        log_info "Check logs with: cd $DOCKER_DIR && docker compose logs -f odoo"
    fi
}

# Restart bare-metal service
restart_bare_metal() {
    local service=$(get_bare_metal_service)

    log_step "Restarting Odoo service: $service..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would restart $service"
        return
    fi

    # Restart service
    systemctl restart "$service"

    # Wait for service to start
    log_info "Waiting for $service to start..."
    sleep 5

    # Check service status
    if systemctl is-active --quiet "$service"; then
        log_info "$service restarted successfully"
    else
        log_error "$service failed to start"
        log_info "Check logs with: journalctl -u $service -n 50"
        exit 1
    fi
}

# Restart service based on deployment type
restart_service() {
    if [[ "$AUTO_RESTART" == false ]]; then
        log_info "Auto-restart disabled (--no-restart)"
        log_warn "Remember to restart manually when ready"
        return
    fi

    case "$DEPLOYMENT_TYPE" in
        docker)
            restart_docker
            ;;
        bare-metal)
            restart_bare_metal
            ;;
        *)
            log_error "Unknown deployment type: $DEPLOYMENT_TYPE"
            exit 1
            ;;
    esac
}

# Health check
health_check() {
    log_step "Running post-deployment health check..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would run health check"
        return
    fi

    local port=$ODOO_PORT
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        port=8070
    else
        port=8069
    fi

    # Check if port is listening
    if command -v nc &> /dev/null; then
        if nc -z localhost "$port" 2>/dev/null; then
            log_info "Odoo is listening on port $port"
        else
            log_warn "Odoo may not be listening on port $port"
        fi
    fi

    # Check service/process status
    case "$DEPLOYMENT_TYPE" in
        docker)
            cd "$DOCKER_DIR"
            if docker compose ps | grep -q "Up"; then
                log_info "Docker containers are running"
            else
                log_warn "Some containers may not be running"
                docker compose ps
            fi
            ;;
        bare-metal)
            local service=$(get_bare_metal_service)
            if systemctl is-active --quiet "$service"; then
                log_info "Service $service is running"
            else
                log_warn "Service $service may not be running"
            fi
            ;;
    esac
}

# Show final summary
show_final_summary() {
    echo ""
    log_deploy "=========================================="
    log_deploy "   Deployment Complete"
    log_deploy "=========================================="
    echo ""

    log_deploy "Environment: $ENVIRONMENT"
    log_deploy "Deployment Type: $DEPLOYMENT_TYPE"
    log_deploy "Branch: $BRANCH"
    log_deploy "Repository: $LOCAL_REPO_PATH"
    echo ""

    if [[ "$AUTO_RESTART" == true ]]; then
        log_deploy "Service Status: Restarted"
    else
        log_warn "Service Status: Manual restart required"
    fi
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] No actual changes were made"
    fi

    log_info "Next steps:"
    log_info "  1. Verify Odoo is accessible"
    log_info "  2. Check logs for any errors"
    log_info "  3. Test deployed features"

    case "$DEPLOYMENT_TYPE" in
        docker)
            log_info "  Docker logs: cd $DOCKER_DIR && docker compose logs -f"
            ;;
        bare-metal)
            local service=$(get_bare_metal_service)
            log_info "  Service logs: sudo journalctl -u $service -f"
            ;;
    esac
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=========================================="
    log_info "Odoo Deployment Script"
    log_info "=========================================="
    echo ""

    parse_args "$@"
    detect_repo_path
    detect_deployment_type

    log_info "Deployment Configuration:"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Branch: $BRANCH"
    log_info "  Deployment Type: $DEPLOYMENT_TYPE"
    log_info "  Repository: $LOCAL_REPO_PATH"
    log_info "  Auto Restart: $AUTO_RESTART"
    log_info "  Backup Before: $BACKUP_BEFORE_DEPLOY"
    log_info "  Dry Run: $DRY_RUN"
    echo ""

    read -p "Continue with deployment? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment aborted"
        exit 0
    fi

    pre_deployment_checks
    create_backup
    pull_changes
    show_deployment_summary
    restart_service
    health_check
    show_final_summary
}

main "$@"
