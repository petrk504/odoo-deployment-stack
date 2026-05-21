# Automation Scripts for Odoo 18 Deployment

Collection of scripts and automation tools for managing Odoo 18 instances.

---

## 📜 Available Scripts

| Script | Purpose | Usage |
|:-------|:--------|:------|
| `install-odoo-prod.sh` | Full production instance setup | One-time deployment |
| `deploy-update.sh` | Deploy code updates | Regular deployments |
| `backup-database.sh` | Database backup | Daily via cron |
| `health-check.sh` | Monitor instance health | Monitoring |

---

## 🚀 Production Installation Script

### install-odoo-prod.sh

Complete automated setup for a new production instance.

**Location:** `/root/install-odoo-prod.sh`

```bash
#!/bin/bash

# ============================================================================
# Odoo 18 Production Instance - Automated Installation
# ============================================================================
# This script performs a complete production installation including:
# - System dependencies
# - Caddy reverse proxy with automatic SSL
# - Isolated system user and PostgreSQL user
# - Python virtual environment
# - Odoo 18 source code
# - Custom addons from GitHub
# - Systemd service configuration
# - Firewall setup
# ============================================================================

set -e  # Exit on any error

# === Configuration Variables ===
CLIENT_NAME="myclient-prod"
DOMAIN_PROD="prod.example.com"
PORT_PROD="8070"
USER_NAME="odoo-prod"
EMAIL="admin@your-domain.com"

# GitHub Repositories
CUSTOM_REPO="git@github.com:petrk504/odoo-deployment-stack.git"
ODOO_REPO="https://github.com/odoo/odoo.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# === Helper Functions ===
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# === Main Installation ===
main() {
    check_root
    
    log_info "Starting Full Production Installation for $CLIENT_NAME..."
    echo ""
    
    # 1. System Dependencies
    log_info "📦 Installing system dependencies..."
    apt-get update -qq
    apt-get install -y -qq \
      build-essential wget git \
      python3.12 python3-pip python3-dev python3-venv python3-wheel \
      libfreetype6-dev libxml2-dev libzip-dev libsasl2-dev \
      python3-setuptools libjpeg-dev zlib1g-dev libpq-dev \
      libxslt1-dev libldap2-dev libtiff5-dev libopenjp2-7-dev \
      postgresql npm node-less \
      debian-keyring debian-archive-keyring apt-transport-https curl \
      > /dev/null 2>&1
    
    # 2. Install Caddy
    log_info "🌐 Installing Caddy reverse proxy..."
    if ! command -v caddy &> /dev/null; then
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | \
            gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | \
            tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
        apt-get update -qq
        apt-get install -y -qq caddy > /dev/null 2>&1
    else
        log_warn "Caddy already installed"
    fi
    
    # 3. Install Wkhtmltopdf
    log_info "📄 Installing Wkhtmltopdf (patched version)..."
    if ! command -v wkhtmltopdf &> /dev/null; then
        cd /tmp
        wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
        dpkg -i wkhtmltox_0.12.6.1-3.jammy_amd64.deb 2>/dev/null || true
        apt-get install -f -y -qq > /dev/null 2>&1
        hash -r
        rm wkhtmltox_0.12.6.1-3.jammy_amd64.deb
    else
        log_warn "Wkhtmltopdf already installed"
    fi
    
    # 4. Create System User
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "👤 Creating system user $USER_NAME..."
        useradd -m -U -r -d /opt/$USER_NAME -s /bin/bash "$USER_NAME"
    else
        log_warn "User $USER_NAME already exists"
    fi
    
    # 5. Create PostgreSQL User
    log_info "🗄️ Creating PostgreSQL user..."
    systemctl start postgresql
    systemctl enable postgresql > /dev/null 2>&1
    sudo -u postgres createuser -s "$USER_NAME" 2>/dev/null || log_warn "PostgreSQL user already exists"
    
    # 6. Setup Directories and Clone Repositories
    log_info "📂 Setting up directories and cloning repositories..."
    sudo -u "$USER_NAME" bash <<EOF
set -e
cd /opt/$USER_NAME

# Clone Odoo 18 Source
if [ ! -d "odoo" ]; then
    echo "  → Cloning Odoo 18..."
    git clone "$ODOO_REPO" --depth 1 --branch 18.0 odoo --quiet
else
    echo "  → Odoo already cloned"
fi

# Clone Custom Addons
if [ ! -d "custom-addons" ]; then
    echo "  → Cloning custom addons..."
    git clone "$CUSTOM_REPO" custom-addons --quiet
else
    echo "  → Custom addons already cloned"
fi

# Create Python Virtual Environment
echo "  → Creating Python virtual environment..."
python3.12 -m venv odoo-venv

# Install Dependencies
echo "  → Installing Python dependencies (this may take a few minutes)..."
source odoo-venv/bin/activate
pip install --upgrade pip --quiet
pip install wheel --quiet
pip install -r odoo/requirements.txt --quiet

# Install custom addons requirements if they exist
if [ -f "custom-addons/requirements.txt" ]; then
    pip install -r custom-addons/requirements.txt --quiet
fi

deactivate
EOF
    
    # 7. Create Log Directory
    log_info "📝 Setting up logging..."
    mkdir -p /var/log/$USER_NAME/
    chown -R $USER_NAME:$USER_NAME /var/log/$USER_NAME/
    
    # 8. Create Odoo Configuration
    log_info "⚙️ Creating Odoo configuration..."
    cat > /etc/$USER_NAME.conf <<EOF
[options]
db_user = $USER_NAME
db_host = False
db_port = False
xmlrpc_port = $PORT_PROD
logfile = /var/log/$USER_NAME/odoo.log
proxy_mode = True
addons_path = /opt/$USER_NAME/odoo/addons,/opt/$USER_NAME/custom-addons
EOF
    
    # 9. Create Systemd Service
    log_info "🔧 Creating systemd service..."
    cat > /etc/systemd/system/$USER_NAME.service <<EOF
[Unit]
Description=Odoo 18 Production - $CLIENT_NAME
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
User=$USER_NAME
Group=$USER_NAME
ExecStart=/opt/$USER_NAME/odoo-venv/bin/python /opt/$USER_NAME/odoo/odoo-bin -c /etc/$USER_NAME.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    # 10. Configure Caddy
    log_info "🌐 Configuring Caddy reverse proxy..."
    if [ ! -f /etc/caddy/Caddyfile ]; then
        cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN_PROD {
    reverse_proxy 127.0.0.1:$PORT_PROD
}
EOF
    else
        if ! grep -q "$DOMAIN_PROD" /etc/caddy/Caddyfile; then
            cat >> /etc/caddy/Caddyfile <<EOF

$DOMAIN_PROD {
    reverse_proxy 127.0.0.1:$PORT_PROD
}
EOF
        else
            log_warn "Domain already in Caddyfile"
        fi
    fi
    
    # 11. Start Services
    log_info "🚀 Starting services..."
    systemctl daemon-reload
    systemctl enable --now $USER_NAME
    systemctl enable --now caddy
    
    # 12. Configure Firewall
    log_info "🔥 Configuring firewall..."
    ufw --force enable > /dev/null 2>&1
    ufw allow 22/tcp > /dev/null 2>&1  # SSH
    ufw allow 80/tcp > /dev/null 2>&1  # HTTP
    ufw allow 443/tcp > /dev/null 2>&1 # HTTPS
    ufw delete allow $PORT_PROD/tcp 2>/dev/null || true
    ufw reload > /dev/null 2>&1
    
    # 13. Wait for SSL
    log_info "🔒 Waiting for SSL certificate (30 seconds)..."
    sleep 30
    
    # 14. Verify Installation
    echo ""
    echo "=========================================="
    echo "  ✅ Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Domain:   https://$DOMAIN_PROD"
    echo "User:     $USER_NAME"
    echo "Port:     $PORT_PROD (internal)"
    echo "Config:   /etc/$USER_NAME.conf"
    echo "Service:  $USER_NAME.service"
    echo "Logs:     /var/log/$USER_NAME/odoo.log"
    echo ""
    echo "Verify service status:"
    echo "  sudo systemctl status $USER_NAME"
    echo ""
    echo "View logs:"
    echo "  sudo tail -f /var/log/$USER_NAME/odoo.log"
    echo ""
    echo "=========================================="
}

# Run installation
main "$@"
```

**Usage:**
```bash
# Download and edit
wget https://raw.githubusercontent.com/YOUR_REPO/install-odoo-prod.sh
nano install-odoo-prod.sh  # Update variables

# Make executable
chmod +x install-odoo-prod.sh

# Run
sudo ./install-odoo-prod.sh
```

---

## 🔄 Deployment Update Script

### deploy-update.sh

Quick deployment script for code updates.

```bash
#!/bin/bash

# ============================================================================
# Odoo 18 Deployment Update Script
# ============================================================================
# Pulls latest code from GitHub and restarts the service
# Usage: ./deploy-update.sh [test|prod]
# ============================================================================

set -e

INSTANCE="${1:-test}"

if [ "$INSTANCE" = "test" ]; then
    USER_NAME="odoo18"
    SERVICE_NAME="odoo18"
    ADDONS_PATH="/opt/odoo18/odoo18-custom-addons"
    VENV_PATH="/opt/odoo18/odoo18-venv"
elif [ "$INSTANCE" = "prod" ]; then
    USER_NAME="odoo-prod"
    SERVICE_NAME="odoo-prod"
    ADDONS_PATH="/opt/odoo-prod/custom-addons"
    VENV_PATH="/opt/odoo-prod/odoo-venv"
else
    echo "Usage: $0 [test|prod]"
    exit 1
fi

echo "🚀 Deploying updates to $INSTANCE instance..."

# Pull latest code
echo "📥 Pulling latest code..."
sudo -u $USER_NAME git -C $ADDONS_PATH pull origin main

# Check if requirements.txt changed
if sudo -u $USER_NAME git -C $ADDONS_PATH diff HEAD@{1} HEAD --name-only | grep -q "requirements.txt"; then
    echo "📦 Requirements changed, updating dependencies..."
    sudo -u $USER_NAME bash <<EOF
source $VENV_PATH/bin/activate
pip install -r $ADDONS_PATH/requirements.txt --quiet
deactivate
EOF
fi

# Restart service
echo "🔄 Restarting service..."
sudo systemctl restart $SERVICE_NAME

# Wait and check status
sleep 2
if sudo systemctl is-active --quiet $SERVICE_NAME; then
    echo "✅ Deployment successful!"
    echo "📊 Service status:"
    sudo systemctl status $SERVICE_NAME --no-pager -l
else
    echo "❌ Deployment failed - service not running"
    echo "📋 Checking logs..."
    sudo tail -20 /var/log/$USER_NAME/odoo*.log
    exit 1
fi
```

**Usage:**
```bash
chmod +x deploy-update.sh

# Deploy to test instance
./deploy-update.sh test

# Deploy to production instance
./deploy-update.sh prod
```

---

## 💾 Database Backup Script

### backup-database.sh

Automated database backup with rotation.

```bash
#!/bin/bash

# ============================================================================
# Odoo Database Backup Script
# ============================================================================
# Creates timestamped backups and removes old ones
# Usage: ./backup-database.sh <database_name> [retention_days]
# ============================================================================

set -e

DATABASE="${1}"
RETENTION_DAYS="${2:-7}"  # Default 7 days
BACKUP_DIR="/home/backups/databases"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${DATABASE}_${TIMESTAMP}.sql"

if [ -z "$DATABASE" ]; then
    echo "Usage: $0 <database_name> [retention_days]"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "🗄️ Backing up database: $DATABASE"
echo "📁 Backup location: $BACKUP_FILE"

# Create backup
sudo -u postgres pg_dump "$DATABASE" | gzip > "${BACKUP_FILE}.gz"

if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(du -h "${BACKUP_FILE}.gz" | cut -f1)
    echo "✅ Backup successful! Size: $BACKUP_SIZE"
    
    # Remove old backups
    echo "🧹 Removing backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -name "${DATABASE}_*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete
    
    # List remaining backups
    echo "📋 Current backups:"
    ls -lh "$BACKUP_DIR/${DATABASE}_"*.sql.gz | tail -5
else
    echo "❌ Backup failed!"
    exit 1
fi
```

**Setup Automated Backups:**
```bash
# Make executable
chmod +x backup-database.sh

# Add to crontab
sudo crontab -e

# Add this line for daily backups at 2 AM
0 2 * * * /root/backup-database.sh production_db 7 >> /var/log/backup.log 2>&1
```

**Manual Usage:**
```bash
# Backup with 7 day retention
./backup-database.sh production_db 7

# Backup with 30 day retention
./backup-database.sh production_db 30
```

---

## 🏥 Health Check Script

### health-check.sh

Monitor instance health and send alerts.

```bash
#!/bin/bash

# ============================================================================
# Odoo Health Check Script
# ============================================================================
# Monitors service status, port binding, and SSL certificate
# Returns exit code 0 if healthy, 1 if issues found
# ============================================================================

set -e

INSTANCE="${1:-test}"

if [ "$INSTANCE" = "test" ]; then
    SERVICE_NAME="odoo18"
    PORT="8069"
    DOMAIN="test.example.com"
elif [ "$INSTANCE" = "prod" ]; then
    SERVICE_NAME="odoo-prod"
    PORT="8070"
    DOMAIN="prod.example.com"
else
    echo "Usage: $0 [test|prod]"
    exit 1
fi

HEALTHY=0

echo "🏥 Health Check for $INSTANCE instance"
echo "========================================"

# Check 1: Service Status
echo -n "Service Status: "
if systemctl is-active --quiet $SERVICE_NAME; then
    echo "✅ Running"
else
    echo "❌ Not Running"
    HEALTHY=1
fi

# Check 2: Port Binding
echo -n "Port Binding ($PORT): "
if netstat -tuln | grep -q ":$PORT "; then
    echo "✅ Listening"
else
    echo "❌ Not Listening"
    HEALTHY=1
fi

# Check 3: HTTP Response
echo -n "HTTP Response: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "303" ]; then
    echo "✅ $HTTP_CODE"
else
    echo "❌ $HTTP_CODE"
    HEALTHY=1
fi

# Check 4: SSL Certificate
echo -n "SSL Certificate: "
if command -v openssl &> /dev/null; then
    CERT_EXPIRY=$(echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | \
                  openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ ! -z "$CERT_EXPIRY" ]; then
        echo "✅ Valid until $CERT_EXPIRY"
    else
        echo "⚠️ Unable to verify"
    fi
else
    echo "⚠️ OpenSSL not installed"
fi

# Check 5: Caddy Status
echo -n "Caddy Proxy: "
if systemctl is-active --quiet caddy; then
    echo "✅ Running"
else
    echo "❌ Not Running"
    HEALTHY=1
fi

# Check 6: PostgreSQL
echo -n "PostgreSQL: "
if systemctl is-active --quiet postgresql; then
    echo "✅ Running"
else
    echo "❌ Not Running"
    HEALTHY=1
fi

# Check 7: Disk Space
echo -n "Disk Space: "
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    echo "✅ ${DISK_USAGE}% used"
elif [ "$DISK_USAGE" -lt 90 ]; then
    echo "⚠️ ${DISK_USAGE}% used (warning)"
else
    echo "❌ ${DISK_USAGE}% used (critical)"
    HEALTHY=1
fi

echo "========================================"

if [ $HEALTHY -eq 0 ]; then
    echo "✅ All checks passed - Instance is healthy"
    exit 0
else
    echo "❌ Some checks failed - Instance needs attention"
    exit 1
fi
```

**Usage:**
```bash
chmod +x health-check.sh

# Check test instance
./health-check.sh test

# Check production instance
./health-check.sh prod

# Use in monitoring (exit code 0 = healthy, 1 = unhealthy)
./health-check.sh prod && echo "OK" || echo "FAIL"
```

---

## 📅 Cron Job Examples

### Daily Database Backup
```bash
# Edit crontab
sudo crontab -e

# Daily backup at 2 AM
0 2 * * * /root/backup-database.sh production_db 7 >> /var/log/backup.log 2>&1
```

### Hourly Health Check
```bash
# Edit crontab
sudo crontab -e

# Every hour
0 * * * * /root/health-check.sh prod || echo "Production instance unhealthy!" | mail -s "Odoo Alert" admin@example.com
```

### Weekly Log Rotation
```bash
# Edit crontab
sudo crontab -e

# Every Sunday at 3 AM
0 3 * * 0 truncate -s 0 /var/log/odoo-prod/odoo.log && systemctl restart odoo-prod
```

---

## 🔧 Utility Commands

### Quick One-Liners

```bash
# Deploy and restart (test)
sudo -u odoo18 git -C /opt/odoo18/odoo18-custom-addons pull origin main && sudo systemctl restart odoo18

# Deploy and restart (production)
sudo -u odoo-prod git -C /opt/odoo-prod/custom-addons pull origin main && sudo systemctl restart odoo-prod

# Backup all databases
for db in $(sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';"); do ./backup-database.sh $db 7; done

# Check all services
sudo systemctl status odoo18 odoo-prod caddy postgresql --no-pager
```

---

## 📝 Script Templates

### Create Custom Installation Script

To create a script for a new client:

```bash
#!/bin/bash
# Based on install-odoo-prod.sh template

CLIENT_NAME="newclient-prod"
DOMAIN_PROD="prod.newclient.com"
PORT_PROD="8071"  # Increment for each client
USER_NAME="odoo-newclient"
EMAIL="admin@newclient.com"
CUSTOM_REPO="git@github.com:user/newclient-repo.git"

# ... rest of script same as install-odoo-prod.sh
```

---

## 🔗 Related Documentation

- **[README.md](./README.md)** - Main maintenance guide
- **[PRODUCTION-SETUP.md](./PRODUCTION-SETUP.md)** - Manual setup guide
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Common issues

---

**Last Updated:** February 2026  
**Maintained by:** Client Company
