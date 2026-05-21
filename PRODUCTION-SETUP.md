# Production Instance Setup Guide

Complete guide for deploying isolated Odoo 18 production instances on Ubuntu 24.04.

---

## 🎯 Overview

This setup ensures complete isolation between:
- Development/Test environments
- Production instances
- Multiple client deployments

**Current Production Instance:**
- **Client:** Palma Azul
- **User:** `odoo-prod`
- **Domain:** prod.example.com
- **Port:** 8070
- **Repository:** git@github.com:petrk504/odoo-deployment-stack.git

---

## 📋 Prerequisites

Before running the installation script, ensure:

1. **DNS Records:** Your domain points to the server IP
2. **SSH Access:** You can connect to the server as a sudo user
3. **GitHub Access:** Server has SSH keys or HTTPS access to your repositories
4. **Email:** Valid email for SSL certificate notifications

---

## 🚀 Quick Production Setup

### Option 1: Automated Installation Script

Use the provided script for a fully automated setup.

**1. Download the script:**
```bash
wget https://raw.githubusercontent.com/YOUR_REPO/install-odoo-prod.sh
# Or create it manually (see script below)
```

**2. Edit configuration variables:**
```bash
nano install-odoo-prod.sh

# Update these values:
CLIENT_NAME="your-client-name"
DOMAIN_PROD="prod.yourclient.com"
PORT_PROD="8070"
EMAIL="admin@yourdomain.com"
```

**3. Make executable and run:**
```bash
chmod +x install-odoo-prod.sh
./install-odoo-prod.sh
```

**4. Script will:**
- ✅ Install system dependencies
- ✅ Install Caddy for reverse proxy
- ✅ Create isolated system user
- ✅ Clone Odoo source and custom repos
- ✅ Set up Python virtual environment
- ✅ Create configuration files
- ✅ Configure systemd service
- ✅ Set up Caddy with automatic SSL
- ✅ Configure firewall

---

## 📜 Complete Installation Script

**File:** `install-odoo-prod.sh`

```bash
#!/bin/bash

# === Configuration Variables ===
CLIENT_NAME="myclient-prod"
DOMAIN_PROD="prod.example.com"
PORT_PROD="8070"
USER_NAME="odoo-prod"
EMAIL="admin@your-domain.com"  # For SSL certificate renewal alerts

# Custom repository (update this for each client)
CUSTOM_REPO="git@github.com:petrk504/odoo-deployment-stack.git"

# Odoo repository (usually stays the same)
ODOO_REPO="https://github.com/odoo/odoo.git"

echo "🚀 Starting Full Production Installation for $CLIENT_NAME..."

# 1. Install System Dependencies
echo "📦 Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
  build-essential wget git \
  python3.12 python3-pip python3-dev python3-venv python3-wheel \
  libfreetype6-dev libxml2-dev libzip-dev libsasl2-dev \
  python3-setuptools libjpeg-dev zlib1g-dev libpq-dev \
  libxslt1-dev libldap2-dev libtiff5-dev libopenjp2-7-dev \
  postgresql npm node-less \
  debian-keyring debian-archive-keyring apt-transport-https curl

# 2. Install Caddy
echo "🌐 Installing Caddy reverse proxy..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update
sudo apt-get install -y caddy

# 3. Install Wkhtmltopdf (Patched Version)
echo "📄 Installing Wkhtmltopdf..."
cd /tmp
wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo dpkg -i wkhtmltox_0.12.6.1-3.jammy_amd64.deb 2>/dev/null || true
sudo apt-get install -f -y
hash -r

# 4. Create System User
if ! id "$USER_NAME" &>/dev/null; then
    echo "👤 Creating system user $USER_NAME..."
    sudo useradd -m -U -r -d /opt/$USER_NAME -s /bin/bash "$USER_NAME"
else
    echo "User $USER_NAME already exists."
fi

# 5. Create PostgreSQL User
echo "🗄️ Creating PostgreSQL user..."
sudo -u postgres createuser -s "$USER_NAME" 2>/dev/null || echo "PostgreSQL user already exists."

# 6. Setup Directories and Clone Repositories
echo "📂 Setting up directories and cloning repositories..."
sudo -u "$USER_NAME" bash <<EOF
cd /opt/$USER_NAME

# Clone Odoo 18 Source
if [ ! -d "odoo" ]; then
    echo "Cloning Odoo 18..."
    git clone "$ODOO_REPO" --depth 1 --branch 18.0 odoo
fi

# Clone Custom Addons
if [ ! -d "custom-addons" ]; then
    echo "Cloning custom addons..."
    git clone "$CUSTOM_REPO" custom-addons
fi

# Create Python Virtual Environment
echo "🐍 Creating Python virtual environment..."
python3.12 -m venv odoo-venv

# Install Dependencies
echo "📚 Installing Python dependencies..."
source odoo-venv/bin/activate
pip install --upgrade pip
pip install wheel
pip install -r odoo/requirements.txt

# Install custom addons requirements if they exist
if [ -f "custom-addons/requirements.txt" ]; then
    pip install -r custom-addons/requirements.txt
fi

deactivate
EOF

# 7. Create Log Directory
echo "📝 Setting up logging..."
sudo mkdir -p /var/log/$USER_NAME/
sudo chown -R $USER_NAME:$USER_NAME /var/log/$USER_NAME/

# 8. Create Odoo Configuration File
echo "⚙️ Creating Odoo configuration..."
sudo tee /etc/$USER_NAME.conf > /dev/null <<EOF
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
echo "🔧 Creating systemd service..."
sudo tee /etc/systemd/system/$USER_NAME.service > /dev/null <<EOF
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

# 10. Configure Caddy Reverse Proxy
echo "🌐 Configuring Caddy..."

# Check if Caddyfile exists, create or update it
if [ ! -f /etc/caddy/Caddyfile ]; then
    sudo tee /etc/caddy/Caddyfile > /dev/null <<EOF
$DOMAIN_PROD {
    reverse_proxy 127.0.0.1:$PORT_PROD
}
EOF
else
    # Append to existing Caddyfile if not already present
    if ! sudo grep -q "$DOMAIN_PROD" /etc/caddy/Caddyfile; then
        sudo tee -a /etc/caddy/Caddyfile > /dev/null <<EOF

$DOMAIN_PROD {
    reverse_proxy 127.0.0.1:$PORT_PROD
}
EOF
    fi
fi

# 11. Start Services
echo "🚀 Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable --now $USER_NAME
sudo systemctl enable --now caddy

# 12. Configure Firewall
echo "🔥 Configuring firewall..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
# Remove direct port access if it exists
sudo ufw delete allow $PORT_PROD/tcp 2>/dev/null || true
sudo ufw reload

# 13. Wait for SSL certificate
echo "🔒 Waiting for SSL certificate (30 seconds)..."
sleep 30

# 14. Verify Installation
echo ""
echo "✅ Installation Complete!"
echo ""
echo "=========================================="
echo "  Production Instance Information"
echo "=========================================="
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
```

---

## 🔧 Manual Installation Steps

If you prefer to understand each step or customize the installation:

### 1. Create System User

```bash
sudo useradd -m -U -r -d /opt/odoo-prod -s /bin/bash odoo-prod
```

### 2. Create PostgreSQL User

```bash
sudo -u postgres createuser -s odoo-prod
```

### 3. Clone Repositories

```bash
sudo -u odoo-prod bash <<EOF
cd /opt/odoo-prod
git clone https://github.com/odoo/odoo.git --depth 1 --branch 18.0 odoo
git clone git@github.com:YOUR_REPO/custom-addons.git custom-addons
EOF
```

### 4. Set Up Python Environment

```bash
sudo -u odoo-prod bash <<EOF
cd /opt/odoo-prod
python3.12 -m venv odoo-venv
source odoo-venv/bin/activate
pip install --upgrade pip wheel
pip install -r odoo/requirements.txt
pip install -r custom-addons/requirements.txt
deactivate
EOF
```

### 5. Create Log Directory

```bash
sudo mkdir -p /var/log/odoo-prod/
sudo chown -R odoo-prod:odoo-prod /var/log/odoo-prod/
```

### 6. Create Configuration File

```bash
sudo nano /etc/odoo-prod.conf
```

**Paste:**
```ini
[options]
db_user = odoo-prod
db_host = False
db_port = False
xmlrpc_port = 8070
logfile = /var/log/odoo-prod/odoo.log
proxy_mode = True
addons_path = /opt/odoo-prod/odoo/addons,/opt/odoo-prod/custom-addons
```

### 7. Create Systemd Service

```bash
sudo nano /etc/systemd/system/odoo-prod.service
```

**Paste:**
```ini
[Unit]
Description=Odoo 18 Production Instance
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
User=odoo-prod
Group=odoo-prod
ExecStart=/opt/odoo-prod/odoo-venv/bin/python /opt/odoo-prod/odoo/odoo-bin -c /etc/odoo-prod.conf
Restart=always

[Install]
WantedBy=multi-user.target
```

### 8. Configure Caddy

```bash
sudo nano /etc/caddy/Caddyfile
```

**Add:**
```
prod.example.com {
    reverse_proxy 127.0.0.1:8070
}
```

### 9. Start Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now odoo-prod
sudo systemctl restart caddy
```

### 10. Configure Firewall

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

---

## 🔐 Security Best Practices

### 1. PostgreSQL Database Password

Set a password for the production database user:

```bash
sudo su - postgres
psql
ALTER USER "odoo-prod" WITH PASSWORD 'strong_password_here';
\q
logout
```

Update `/etc/odoo-prod.conf`:
```ini
db_password = strong_password_here
```

### 2. Odoo Admin Password

Set master password in `/etc/odoo-prod.conf`:
```ini
admin_passwd = your_super_strong_master_password
```

Or use environment variables in the service file:
```ini
Environment="ODOO_ADMIN_PASSWD=your_master_password"
```

### 3. Limit Database List

After creating your production database:
```ini
dbfilter = ^production_db_name$
list_db = False
```

### 4. Firewall Rules

Ensure only Caddy ports are exposed:
```bash
sudo ufw status numbered

# Should show:
# 22/tcp  (SSH)
# 80/tcp  (HTTP)
# 443/tcp (HTTPS)

# Ports 8069, 8070 should NOT be in the list
```

---

## 📊 Deployment Workflow

### Initial Deployment

1. **Push code to GitHub**
2. **Run installation script** on server
3. **Create database** in Odoo UI
4. **Install modules** needed
5. **Configure** settings
6. **Backup database**

### Regular Updates

```bash
# 1. Pull latest code
sudo -u odoo-prod git -C /opt/odoo-prod/custom-addons pull origin main

# 2. Update dependencies if needed
sudo -u odoo-prod /opt/odoo-prod/odoo-venv/bin/pip install -r /opt/odoo-prod/custom-addons/requirements.txt

# 3. Restart service
sudo systemctl restart odoo-prod

# 4. Verify
sudo systemctl status odoo-prod
sudo tail -f /var/log/odoo-prod/odoo.log
```

---

## 🔄 Adding Multiple Production Clients

To add a second production instance for a different client:

1. **Update script variables:**
```bash
CLIENT_NAME="newclient-prod"
DOMAIN_PROD="prod.newclient.com"
PORT_PROD="8071"  # Use different port
USER_NAME="odoo-newclient"
CUSTOM_REPO="git@github.com:user/newclient-repo.git"
```

2. **Run script again** - it's fully isolated

3. **Update Caddy** to add new domain

Result: Completely isolated instances with:
- Separate users
- Separate databases
- Separate ports
- Separate domains
- Separate code repositories

---

## 🧪 Testing Production Setup

### Verify Services

```bash
# Check Odoo service
sudo systemctl status odoo-prod

# Check Caddy
sudo systemctl status caddy

# Check port binding
sudo netstat -tulpn | grep 8070

# Check PostgreSQL
sudo systemctl status postgresql
```

### Verify SSL Certificate

```bash
# Check certificate details
curl -vI https://prod.example.com 2>&1 | grep -i 'SSL\|certificate'

# Test HTTPS redirect
curl -I http://prod.example.com
# Should show: Location: https://...
```

### Verify Logs

```bash
# Check for errors
sudo tail -100 /var/log/odoo-prod/odoo.log

# Follow live logs
sudo journalctl -u odoo-prod -f
```

### Create Test Database

1. Visit `https://prod.example.com`
2. Create database
3. Install "Contacts" app
4. Verify it works

---

## 📦 Backup Strategy

### Database Backups

```bash
# Manual backup
sudo -u odoo-prod pg_dump DATABASE_NAME > ~/prod_backup_$(date +%Y%m%d).sql

# Automated daily backup (cron)
sudo crontab -e -u odoo-prod

# Add:
0 2 * * * pg_dump DATABASE_NAME > ~/backups/prod_$(date +\%Y\%m\%d).sql
```

### File Backups

```bash
# Backup custom addons
sudo -u odoo-prod tar -czf ~/custom_addons_$(date +%Y%m%d).tar.gz /opt/odoo-prod/custom-addons

# Backup configuration
sudo tar -czf ~/odoo_config_$(date +%Y%m%d).tar.gz /etc/odoo-prod.conf /etc/systemd/system/odoo-prod.service
```

---

## 🔗 Related Documentation

- **[README.md](./README.md)** - Main maintenance guide
- **[install-odoo-18.md](./install-odoo-18.md)** - Test instance installation
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Common issues and solutions
- **[AUTOMATION.md](./AUTOMATION.md)** - Scripts and automation

---

**Last Updated:** February 2026  
**Maintained by:** Client Company
