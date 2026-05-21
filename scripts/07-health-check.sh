#!/bin/bash
################################################################################
# Odoo Health Check and Monitoring Script
# Purpose: Monitor Odoo instances and provide health diagnostics
#
# Supports both Docker and bare-metal deployments.
# Can be run manually or via cron for automated monitoring.
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
ENVIRONMENT=${ENVIRONMENT:-all}  # all, test, prod
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE:-auto}  # auto, docker, bare-metal

# Alert thresholds
CPU_WARNING=70
CPU_CRITICAL=90
RAM_WARNING=70
RAM_CRITICAL=85
DISK_WARNING=80
DISK_CRITICAL=90

# Health check settings
ODOO_PORT_TEST=${ODOO_PORT_TEST:-8069}
ODOO_PORT_PROD=${ODOO_PORT_PROD:-8070}
HEALTH_CHECK_TIMEOUT=10
HEALTH_CHECK_RETRIES=3

# Output format
OUTPUT_FORMAT=${OUTPUT_FORMAT:-text}  # text, json, html
ALERT_EMAIL=${ALERT_EMAIL:-""}
ALERT_WEBHOOK=${ALERT_WEBHOOK:-""}

# Docker configuration
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-odoo}
DOCKER_DIR_TEST="${DOCKER_DIR_TEST:-$(pwd)/docker/test}"
DOCKER_DIR_PROD="${DOCKER_DIR_PROD:-$(pwd)/docker/prod}"

# Bare-metal configuration
ODOO_SERVICE_TEST=${ODOO_SERVICE_TEST:-odoo18}
ODOO_SERVICE_PROD=${ODOO_SERVICE_PROD:-odoo-prod}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Alert counters
WARNINGS=0
CRITICALS=0

################################################################################
# LOGGING FUNCTIONS
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[CRIT]${NC} $1"
    ((CRITICALS++))
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

Monitor Odoo instances and provide health diagnostics.

OPTIONS:
    -e, --environment ENV       Environment: all, test, prod [default: all]
    -t, --type TYPE             Deployment type: auto, docker, bare-metal [default: auto]
    -o, --output FORMAT         Output format: text, json, html [default: text]
    --cpu-warning N             CPU warning threshold % [default: 70]
    --cpu-critical N            CPU critical threshold % [default: 90]
    --ram-warning N             RAM warning threshold % [default: 70]
    --ram-critical N            RAM critical threshold % [default: 85]
    --disk-warning N            Disk warning threshold % [default: 80]
    --disk-critical N           Disk critical threshold % [default: 90]
    --email EMAIL               Send alert email (requires mailx)
    --webhook URL               Send alert to webhook URL
    --no-color                  Disable color output
    -h, --help                  Show this help message

EXAMPLES:
    # Check all environments
    $0

    # Check test environment only
    $0 --environment test

    # JSON output for monitoring tools
    $0 --output json

    # With custom thresholds and email alerts
    $0 --cpu-warning 60 --disk-critical 85 --email admin@example.com

THRESHOLDS:
    Thresholds are in percentages. When exceeded, warnings or critical
    alerts are triggered. Critical errors exit with status code 2.

AUTOMATION:
    Add to crontab for automated monitoring:

    # Every 5 minutes
    */5 * * * * /path/to/health-check.sh --environment all --email admin@example.com

    # Every hour with JSON output
    0 * * * * /path/to/health-check.sh --output json > /var/log/odoo-health.json

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
            -t|--type)
                DEPLOYMENT_TYPE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --cpu-warning)
                CPU_WARNING="$2"
                shift 2
                ;;
            --cpu-critical)
                CPU_CRITICAL="$2"
                shift 2
                ;;
            --ram-warning)
                RAM_WARNING="$2"
                shift 2
                ;;
            --ram-critical)
                RAM_CRITICAL="$2"
                shift 2
                ;;
            --disk-warning)
                DISK_WARNING="$2"
                shift 2
                ;;
            --disk-critical)
                DISK_CRITICAL="$2"
                shift 2
                ;;
            --email)
                ALERT_EMAIL="$2"
                shift 2
                ;;
            --webhook)
                ALERT_WEBHOOK="$2"
                shift 2
                ;;
            --no-color)
                RED=''
                GREEN=''
                YELLOW=''
                NC=''
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Check system resources
check_system_resources() {
    log_step "Checking system resources..."
    echo ""

    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    cpu_usage=${cpu_usage%.*}  # Convert to integer

    echo -n "CPU Usage: ${cpu_usage}% "
    if [[ $cpu_usage -ge $CPU_CRITICAL ]]; then
        log_error "(CRITICAL: >${CPU_CRITICAL}%)"
    elif [[ $cpu_usage -ge $CPU_WARNING ]]; then
        log_warn "(WARNING: >${CPU_WARNING}%)"
    else
        echo -e "${GREEN}[OK]${NC}"
    fi

    # RAM usage
    local ram_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')

    echo -n "RAM Usage: ${ram_usage}% "
    if [[ $ram_usage -ge $RAM_CRITICAL ]]; then
        log_error "(CRITICAL: >${RAM_CRITICAL}%)"
    elif [[ $ram_usage -ge $RAM_WARNING ]]; then
        log_warn "(WARNING: >${RAM_WARNING}%)"
    else
        echo -e "${GREEN}[OK]${NC}"
    fi

    # Swap usage
    local swap_total=$(free | grep Swap | awk '{print $2}')
    if [[ $swap_total -gt 0 ]]; then
        local swap_used=$(free | grep Swap | awk '{print $3}')
        local swap_usage=$((swap_used * 100 / swap_total))

        echo -n "Swap Usage: ${swap_usage}% "
        if [[ $swap_usage -gt 50 ]]; then
            log_warn "(High swap usage indicates memory pressure)"
        else
            echo -e "${GREEN}[OK]${NC}"
        fi
    else
        log_warn "No swap configured"
    fi

    # Disk usage
    echo ""
    echo "Disk Usage:"
    df -h | grep -E '^/dev/' | while read line; do
        local usage=$(echo $line | awk '{print $5}' | tr -d '%')
        local mount=$(echo $line | awk '{print $6}')

        echo -n "  $mount: ${usage}% "
        if [[ $usage -ge $DISK_CRITICAL ]]; then
            log_error "(CRITICAL: >${DISK_CRITICAL}%)"
        elif [[ $usage -ge $DISK_WARNING ]]; then
            log_warn "(WARNING: >${DISK_WARNING}%)"
        else
            echo -e "${GREEN}[OK]${NC}"
        fi
    done

    echo ""
}

# Check Docker deployment
check_docker_deployment() {
    local env="$1"
    local docker_dir="$2"
    local port="$3"

    log_step "Checking Docker deployment: $env"
    echo ""

    if [[ ! -d "$docker_dir" ]]; then
        log_warn "Docker directory not found: $docker_dir"
        return
    fi

    cd "$docker_dir"

    # Check containers
    echo "Containers:"
    if docker compose ps | grep -q "Up"; then
        docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    else
        log_error "No containers running"
        return
    fi
    echo ""

    # Check Odoo container health
    local container_name="${COMPOSE_PROJECT_NAME}-${env}-odoo"
    if docker ps --format '{{.Names}}' | grep -q "$container_name"; then
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-healthcheck")

        echo -n "Odoo Container Health: $health_status "
        if [[ "$health_status" == "healthy" ]]; then
            echo -e "${GREEN}[OK]${NC}"
        elif [[ "$health_status" == "starting" ]]; then
            log_warn "(Container is starting)"
        else
            log_error "(Container unhealthy or not responding)"
        fi
    fi

    # Check database container
    local db_container="${COMPOSE_PROJECT_NAME}-${env}-db"
    if docker ps --format '{{.Names}}' | grep -q "$db_container"; then
        if docker compose exec -T db pg_isready &>/dev/null; then
            echo -e "Database: ${GREEN}[OK]${NC}"
        else
            log_error "Database not responding"
        fi
    fi

    # Check HTTP endpoint
    echo -n "HTTP Endpoint (port $port): "
    if command -v curl &> /dev/null; then
        if curl -s --max-time $HEALTH_CHECK_TIMEOUT "http://localhost:$port" | head -1 | grep -q "DOCTYPE\|xml"; then
            echo -e "${GREEN}[OK]${NC}"
        else
            log_error "(Not responding or returning errors)"
        fi
    else
        echo "Skipped (curl not available)"
    fi

    echo ""
}

# Check bare-metal deployment
check_bare_metal_deployment() {
    local env="$1"
    local service="$2"
    local port="$3"

    log_step "Checking bare-metal deployment: $env"
    echo ""

    # Check service status
    echo -n "Service Status ($service): "
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}[OK]${NC}"
    else
        log_error "(Service not running)"
        return
    fi

    # Check service is listening on port
    echo -n "Listening on port $port: "
    if command -v ss &> /dev/null; then
        if ss -tlnp | grep -q ":$port "; then
            echo -e "${GREEN}[OK]${NC}"
        else
            log_error "(Not listening on port $port)"
        fi
    else
        echo "Skipped (ss not available)"
    fi

    # Check HTTP endpoint
    echo -n "HTTP Endpoint: "
    if command -v curl &> /dev/null; then
        local response=$(curl -s --max-time $HEALTH_CHECK_TIMEOUT "http://localhost:$port" | head -1)
        if echo "$response" | grep -q "DOCTYPE\|xml"; then
            echo -e "${GREEN}[OK]${NC}"
        else
            log_error "(Not responding or returning errors)"
        fi
    else
        echo "Skipped (curl not available)"
    fi

    # Show service status details
    echo ""
    echo "Service Details:"
    systemctl status "$service" --no-pager | head -n 5

    echo ""
}

# Check logs for errors
check_logs() {
    log_step "Checking logs for recent errors..."
    echo ""

    # Docker logs
    if [[ -d "$DOCKER_DIR_TEST" ]]; then
        echo "Test Environment Docker Logs (last 10 errors):"
        cd "$DOCKER_DIR_TEST"
        docker compose logs --tail=100 2>/dev/null | grep -i "error\|exception\|critical" | tail -10 || echo "No errors found"
        echo ""
    fi

    # Bare-metal logs
    if [[ -f "/var/log/odoo18/odoo18.log" ]]; then
        echo "Test Environment Bare-Metal Logs (last 10 errors):"
        grep -i "error\|exception\|critical" /var/log/odoo18/odoo18.log | tail -10 || echo "No errors found"
        echo ""
    fi
}

# Send alert
send_alert() {
    local severity="$1"
    local message="$2"

    # Send email
    if [[ -n "$ALERT_EMAIL" ]] && command -v mailx &> /dev/null; then
        echo "$message" | mailx -s "[$severity] Odoo Health Alert" "$ALERT_EMAIL"
    fi

    # Send webhook
    if [[ -n "$ALERT_WEBHOOK" ]] && command -v curl &> /dev/null; then
        curl -s -X POST "$ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"severity\": \"$severity\", \"message\": \"$message\"}" &>/dev/null
    fi
}

# Show summary
show_summary() {
    echo ""
    log_step "Health Check Summary"
    echo ""

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "Timestamp: $timestamp"
    echo "Environment: $ENVIRONMENT"
    echo "Deployment Type: $DEPLOYMENT_TYPE"
    echo "Warnings: $WARNINGS"
    echo "Critical: $CRITICALS"
    echo ""

    if [[ $CRITICALS -gt 0 ]]; then
        log_error "Health check FAILED with $CRITICALS critical error(s)"
        send_alert "CRITICAL" "Odoo health check failed with $CRITICALS critical and $WARNINGS warnings"
        exit 2
    elif [[ $WARNINGS -gt 0 ]]; then
        log_warn "Health check completed with $WARNINGS warning(s)"
        send_alert "WARNING" "Odoo health check completed with $WARNINGS warnings"
        exit 1
    else
        log_info "Health check PASSED - All systems nominal"
        exit 0
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=========================================="
    log_info "Odoo Health Check"
    log_info "=========================================="
    echo ""

    parse_args "$@"

    # Detect deployment type if auto
    if [[ "$DEPLOYMENT_TYPE" == "auto" ]]; then
        if [[ -d "$DOCKER_DIR_TEST" ]]; then
            DEPLOYMENT_TYPE="docker"
        elif systemctl is-active --quiet "$ODOO_SERVICE_TEST"; then
            DEPLOYMENT_TYPE="bare-metal"
        fi
    fi

    check_system_resources

    # Check based on environment
    if [[ "$ENVIRONMENT" == "all" || "$ENVIRONMENT" == "test" ]]; then
        if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
            check_docker_deployment "test" "$DOCKER_DIR_TEST" "$ODOO_PORT_TEST"
        else
            check_bare_metal_deployment "test" "$ODOO_SERVICE_TEST" "$ODOO_PORT_TEST"
        fi
    fi

    if [[ "$ENVIRONMENT" == "all" || "$ENVIRONMENT" == "prod" ]]; then
        if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
            check_docker_deployment "prod" "$DOCKER_DIR_PROD" "$ODOO_PORT_PROD"
        else
            check_bare_metal_deployment "prod" "$ODOO_SERVICE_PROD" "$ODOO_PORT_PROD"
        fi
    fi

    check_logs
    show_summary
}

main "$@"
