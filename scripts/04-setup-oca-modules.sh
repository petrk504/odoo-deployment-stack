#!/bin/bash
################################################################################
# OCA Modules Setup Script
# Purpose: Clone and configure OCA (Odoo Community Association) modules
#
# OCA repos are maintained by the Odoo community and provide additional
# functionality not included in core Odoo.
#
# Author: Petr
# Version: 1.0
# Last Updated: March 2026
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION
################################################################################

# OCA repositories to install
# Format: "repo_name:branch" (branch defaults to 18.0 if not specified)
OCA_REPOS=(
    "social:18.0"                    # mail_gateway_whatsapp
    "account-financial-tools:18.0"   # Accounting enhancements
    "reporting-engine:18.0"          # Custom report generation
    # Add more repos as needed:
    # "server-tools:18.0"             # Server-side tools
    # "web:18.0"                      # Web interface enhancements
    # "hr:18.0"                       # HR modules
)

# Installation paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ADDONS_DIR="${ADDONS_DIR:-${PROJECT_ROOT}/addons/oca}"
ODOO_VERSION=${ODOO_VERSION:-18.0}

# Git configuration
GIT_SSH=${GIT_SSH:-false}           # Use SSH instead of HTTPS
SHALLOW_CLONE=${SHALLOW_CLONE:-true} # Use --depth 1 for faster clones

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

Clone and configure OCA (Odoo Community Association) module repositories.

OPTIONS:
    -a, --addons-dir DIR         OCA addons directory [default: ./addons/oca]
    -v, --version VERSION        Odoo version [default: 18.0]
    -r, --repos "repo1 repo2"    Specific repos to install (space-separated)
    -l, --list                   List available OCA repositories
    -u, --update                 Update existing repositories
    -s, --ssh                    Use SSH instead of HTTPS for git
    -f, --full                   Full clone (no --depth 1)
    -h, --help                   Show this help message

EXAMPLES:
    # Install default repos for Odoo 18.0
    $0

    # Install specific repos
    $0 --repos "social server-tools"

    # Update existing repos
    $0 --update

    # Use SSH for git operations
    $0 --ssh

    # Install to custom directory
    $0 --addons-dir /opt/odoo/addons/oca

AVAILABLE OCA REPOS:
    social                    - WhatsApp, Telegram, email integration
    account-financial-tools   - Accounting, budget, treasury
    reporting-engine          - Aeroo reports, QWeb enhancements
    server-tools              - Automation, scheduled actions
    web                       - Web interface, widgets
    hr                        - HR, payroll, attendance
    sale-workflow             - Sales, invoicing workflows
    stock-logistics-warehouse - Inventory, warehouse management
    purchase-workflow         - Procurement, purchase orders
    project                   - Project management
    marketing                 - Marketing automation
    partner-contact           - CRM, contacts management
    bank-statement-import     - Bank statement import plugins
    l10n-countries            - Localizations (by country)

EOF
}

# Parse command line arguments
parse_args() {
    UPDATE_MODE=false
    LIST_MODE=false
    SPECIFIC_REPOS=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--addons-dir)
                ADDONS_DIR="$2"
                shift 2
                ;;
            -v|--version)
                ODOO_VERSION="$2"
                shift 2
                ;;
            -r|--repos)
                shift
                while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                    SPECIFIC_REPOS+=("$1")
                    shift
                done
                ;;
            -u|--update)
                UPDATE_MODE=true
                shift
                ;;
            -s|--ssh)
                GIT_SSH=true
                shift
                ;;
            -f|--full)
                SHALLOW_CLONE=false
                shift
                ;;
            -l|--list)
                LIST_MODE=true
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

    # Override repos if specific repos provided
    if [[ ${#SPECIFIC_REPOS[@]} -gt 0 ]]; then
        OCA_REPOS=("${SPECIFIC_REPOS[@]}")
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check git
    if ! command -v git &> /dev/null; then
        log_error "git is not installed"
        log_info "Install with: sudo apt install git"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# List available OCA repositories
list_repositories() {
    log_info "=== Popular OCA Repositories for Odoo ${ODOO_VERSION} ==="
    echo ""

    cat << EOF
Core Integration:
  social                    - Social media integration (WhatsApp, Telegram)
  server-tools              - Server automation, scheduled actions
  web                       - Web interface enhancements

Financial:
  account-financial-tools   - Accounting, budget, treasury management
  bank-statement-import     - Bank statement import plugins
  account-invoicing         - Invoicing enhancements

Sales & CRM:
  sale-workflow             - Sales workflow improvements
  partner-contact           - Advanced CRM, contacts management
  marketing                 - Marketing automation

Operations:
  stock-logistics-warehouse - Inventory, warehouse management
  purchase-workflow         - Procurement, purchase orders

Project & HR:
  project                   - Project management enhancements
  hr                        - HR, payroll, attendance

Reporting:
  reporting-engine          - Aeroo reports, QWeb enhancements

Localization:
  l10n-countries            - Localizations by country

To see all available repositories, visit:
  https://github.com/OCA

To install specific repos, use:
  $0 --repos "social server-tools web"
EOF
}

# Create addons directory
create_addons_dir() {
    if [[ ! -d "$ADDONS_DIR" ]]; then
        log_step "Creating OCA addons directory: $ADDONS_DIR"
        mkdir -p "$ADDONS_DIR"
        log_info "Directory created"
    else
        log_info "OCA addons directory exists: $ADDONS_DIR"
    fi
}

# Get git URL (HTTPS or SSH)
get_git_url() {
    local repo_name="$1"

    if [[ "$GIT_SSH" == true ]]; then
        echo "git@github.com:OCA/${repo_name}.git"
    else
        echo "https://github.com/OCA/${repo_name}.git"
    fi
}

# Clone OCA repository
clone_repo() {
    local repo_spec="$1"
    local repo_name="${repo_spec%:*}"
    local branch="${repo_spec#*:}"

    # Default to ODOO_VERSION if no branch specified
    if [[ "$branch" == "$repo_name" ]]; then
        branch="$ODOO_VERSION"
    fi

    local repo_dir="${ADDONS_DIR}/${repo_name}"

    log_step "Processing repository: $repo_name (branch: $branch)"

    # Check if repo already exists
    if [[ -d "$repo_dir" ]]; then
        if [[ "$UPDATE_MODE" == true ]]; then
            log_info "Repository exists, updating..."
            cd "$repo_dir"

            # Get current branch
            local current_branch=$(git rev-parse --abbrev-ref HEAD)

            if [[ "$current_branch" != "$branch" ]]; then
                log_warn "Current branch is '$current_branch', switching to '$branch'"
                git checkout "$branch"
            fi

            # Pull latest changes
            git pull origin "$branch"
            log_info "Repository updated: $repo_name"
        else
            log_info "Repository already exists: $repo_name (use --update to refresh)"
        fi
        return
    fi

    # Clone repository
    local git_url=$(get_git_url "$repo_name")
    local clone_args=""

    if [[ "$SHALLOW_CLONE" == true ]]; then
        clone_args="--depth 1 --single-branch --branch $branch"
    else
        clone_args="--single-branch --branch $branch"
    fi

    log_info "Cloning $repo_name from GitHub..."
    git clone $clone_args "$git_url" "$repo_dir"

    if [[ -d "$repo_dir" ]]; then
        log_info "Successfully cloned: $repo_name"
    else
        log_error "Failed to clone: $repo_name"
        return 1
    fi
}

# Count installed modules
count_modules() {
    local total=0
    local repos_processed=0

    log_step "Counting installed modules..."

    for repo_spec in "${OCA_REPOS[@]}"; do
        local repo_name="${repo_spec%:*}"
        local repo_dir="${ADDONS_DIR}/${repo_name}"

        if [[ -d "$repo_dir" ]]; then
            local module_count=$(find "$repo_dir" -maxdepth 2 -name "__manifest__.py" | wc -l)
            log_info "  $repo_name: $module_count modules"
            ((repos_processed++))
            ((total += module_count))
        fi
    done

    echo ""
    log_info "Total: $total modules across $repos_processed repositories"
}

# Show repository status
show_status() {
    echo ""
    log_info "=== OCA Repositories Status ==="
    echo ""

    for repo_spec in "${OCA_REPOS[@]}"; do
        local repo_name="${repo_spec%:*}"
        local repo_dir="${ADDONS_DIR}/${repo_name}"

        if [[ -d "$repo_dir" ]]; then
            local branch=$(cd "$repo_dir" && git rev-parse --abbrev-ref HEAD)
            local commit=$(cd "$repo_dir" && git log -1 --format="%h - %s (%cr)")
            local module_count=$(find "$repo_dir" -maxdepth 2 -name "__manifest__.py" | wc -l)

            log_info "$repo_name:"
            echo "  Branch: $branch"
            echo "  Modules: $module_count"
            echo "  Latest: $commit"
            echo ""
        fi
    done
}

# Show next steps
show_next_steps() {
    echo ""
    log_info "=== Next Steps ==="
    echo ""
    log_info "1. Review installed modules:"
    log_info "   ls -la $ADDONS_DIR"
    echo ""
    log_info "2. Update Docker Compose configuration:"
    log_info "   Edit docker-compose.yml and ensure addons path includes:"
    log_info "   ./addons/oca/social"
    log_info "   ./addons/oca/account-financial-tools"
    log_info "   ./addons/oca/reporting-engine"
    echo ""
    log_info "3. Restart Odoo containers:"
    log_info "   docker compose restart odoo"
    echo ""
    log_info "4. Update Odoo app list:"
    log_info "   - Go to Apps menu in Odoo"
    log_info "   - Click 'Update Apps List'"
    log_info "   - Install desired OCA modules"
    echo ""
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=========================================="
    log_info "OCA Modules Setup Script"
    log_info "=========================================="
    echo ""

    parse_args "$@"

    if [[ "$LIST_MODE" == true ]]; then
        list_repositories
        exit 0
    fi

    log_info "Configuration:"
    log_info "  ODOO_VERSION: $ODOO_VERSION"
    log_info "  ADDONS_DIR: $ADDONS_DIR"
    log_info "  GIT_SSH: $GIT_SSH"
    log_info "  SHALLOW_CLONE: $SHALLOW_CLONE"
    log_info "  Repositories: ${#OCA_REPOS[@]}"
    echo ""

    check_prerequisites
    create_addons_dir

    log_info "Repositories to process:"
    for repo_spec in "${OCA_REPOS[@]}"; do
        local repo_name="${repo_spec%:*}"
        log_info "  - $repo_name"
    done
    echo ""

    read -p "Continue with OCA repository setup? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi

    # Clone/update each repository
    for repo_spec in "${OCA_REPOS[@]}"; do
        clone_repo "$repo_spec"
    done

    echo ""
    count_modules
    show_status
    show_next_steps

    log_info "OCA modules setup complete!"
}

main "$@"
