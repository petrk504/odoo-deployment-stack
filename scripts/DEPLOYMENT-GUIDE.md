# Odoo 18 Docker Deployment Guide

**Complete production-ready deployment guide for Odoo 18 on Ubuntu 24.04 with Docker.**

*Last Updated: March 17, 2026*

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Post-Installation](#post-installation)
5. [Adding OCA Modules](#adding-oca-modules)
6. [Troubleshooting](#troubleshooting)
7. [Backup & Restore](#backup--restore)

---

## Quick Start

```bash
# 1. Download the installation script
wget https://raw.githubusercontent.com/petrk504/odoo-deployment-stack/main/scripts/install-odoo-docker.sh

# 2. Make it executable
chmod +x install-odoo-docker.sh

# 3. Run installation
sudo ./install-odoo-docker.sh --environment test --domain test.yourdomain.com

# 4. Open browser
# http://localhost:8069
```

---

## Prerequisites

### System Requirements
- **OS:** Ubuntu 24.04 LTS (or similar Debian-based distribution)
- **RAM:** 4GB minimum (tested with 3.8GB)
- **Storage:** 50GB+ SSD
- **Network:** Public IP with domain (optional)

### Software Requirements
- **Docker:** 20.10+ or Docker Compose 2.x
- **Git:** For downloading OCA modules
- **Caddy:** For reverse proxy with SSL (optional but recommended)

---

## Installation

### Option A: Automated Installation (Recommended)

```bash
# 1. Download script
wget https://raw.githubusercontent.com/petrk504/odoo-deployment-stack/main/scripts/install-odoo-docker.sh

# 2. Make executable
chmod +x install-odoo-docker.sh

# 3. Install for test environment
sudo ./install-odoo-docker.sh --environment test --domain test.example.com

# 4. Install for production
sudo ./install-odoo-docker.sh --environment prod --domain prod.example.com
```

### Option B: Manual Installation

See [Manual Installation Guide](#manual-installation) below for detailed steps.

---

## Post-Installation

### Step 1: Create Database

1. **Open your browser** and go to: `http://your-server-ip:8069`

2. **Click "Create database"**

3. **Fill in the details:**
   - Database name: `test` (or `prod`)
   - Email: admin@yourdomain.com
   - Password: (choose a strong password)
   - Language: English (or your preference)
   - Country: Your country

4. **Click "Create"**

5. **Wait for initialization** (1-3 minutes)

6. **You should see the Odoo dashboard!**

---

## Adding OCA Modules

### Step 1: Stop Odoo

```bash
cd ~/odoo-docker/test
docker-compose down
```

### Step 2: Update docker-compose.yml

```bash
nano ~/odoo-docker/test/docker-compose.yml
```

**Find the `command:` line and change it from:**
```yaml
command: --data-dir=/var/lib/odoo --http-interface=0.0.0.0 --http-port=8069 --proxy-mode --without-demo=all --db-filter=^test$$
```

**To:**
```yaml
command: --data-dir=/var/lib/odoo --http-interface=0.0.0.0 --http-port=8069 --proxy-mode --without-demo=all --addons-path=/usr/lib/python3/dist-packages/odoo/addons,/mnt/addons/oca,/mnt/addons/cybrosys --db-filter=^test$$
```

**Save:** Ctrl+X, Y, Enter

### Step 3: Restart Odoo

```bash
cd ~/odoo-docker/test
docker-compose up -d
sleep 15
```

### Step 4: Update Apps in Odoo UI

1. **Go to:** `http://your-server-ip:8069`

2. **Login** with your admin credentials

3. **Go to Apps** (top menu)

4. **Click "Update Apps List"** (top right dropdown)

5. **Check:**
   - ✅ Odoo Apps
   - ✅ OCA Social
   - ✅ OCA Accounting

6. **Click "Update"**

7. **Wait** (1-2 minutes)

### Step 5: Install Modules

**In the Apps search box, type and install:**

- `accounting kit` → "Base Accounting Kit"
- `mail gateway whatsapp` → "WhatsApp Gateway"
- `reporting engine` → "Reporting Engine" (if needed)

---

## Troubleshooting

### Issue 1: Container Keeps Restarting

**Symptoms:**
```bash
sudo docker ps
# Shows: Restarting (1) XX seconds ago
```

**Solution:**
```bash
# Check logs
sudo docker logs odoo-test --tail=100

# Common causes:
# - Wrong addons path (directories don't exist)
# - Database connection issues
# - Permission errors

# Quick fix: Remove addons-path temporarily
# Edit docker-compose.yml and remove --addons-path
# Then restart
```

### Issue 2: "database already exists" Error

**Symptoms:**
- Odoo says database exists but PostgreSQL shows it doesn't

**Solution:**
```bash
# Drop the database and start fresh
cd ~/odoo-docker/test
docker-compose exec db psql -U odoo -d postgres -c "DROP DATABASE test;"
docker-compose restart odoo-test
```

### Issue 3: Permission Denied on Filestore

**Symptoms:**
```bash
PermissionError: [Errno 13] Permission denied: '/var/lib/odoo/filestore/test'
```

**Solution:**
```bash
# Fix permissions
docker exec --user root odoo-test chown -R odoo:odoo /var/lib/odoo/filestore
```

### Issue 4: Can't Access via Domain

**Symptoms:**
- Works via IP but not domain
- 502 Bad Gateway

**Solution:**
```bash
# Check Caddy configuration
sudo cat /etc/caddy/Caddyfile

# Ensure Caddy is pointing to correct port
sudo systemctl restart caddy
```

---

## Backup & Restore

### Manual Backup

```bash
# Backup database
cd ~/odoo-docker/test
docker-compose exec db pg_dump -U odoo test > ~/backups/test_backup_$(date +%Y%m%d).sql

# Backup filestore
docker run --rm \
  -v odoo-test-filestore:/data \
  -v ~/backups:/backup \
  alpine tar czf /backup/filestore_$(date +%Y%m%d).tar.gz -C /data .
```

### Manual Restore

```bash
# Restore database
cd ~/odoo-docker/test
docker-compose exec -T db psql -U odoo test < ~/backups/test_backup_20260317.sql

# Restore filestore
docker run --rm \
  -v odoo-test-filestore:/data \
  -v ~/backups:/backup \
  alpine tar xzf /backup/filestore_20260317.tar.gz -C /data
```

---

## Maintenance

### Updating OCA Modules

```bash
cd ~/addons/oca/social
git pull origin 18.0

# Restart Odoo
cd ~/odoo-docker/test
docker-compose restart
```

### Updating Odoo Image

```bash
# 1. Test on test environment FIRST
cd ~/odoo-docker/test

# 2. Change image in docker-compose.yml
# TEST THOROUGHLY FOR 1-2 WEEKS

# 3. Only then update production
cd ~/odoo-docker/prod
# Update image and restart
```

---

## Security Checklist

- [ ] Changed default passwords in .env file
- [ ] Saved credentials to secure location
- [ ] Configured firewall (ufw)
- [ ] Set up automatic backups
- [ ] SSL enabled (via Caddy)
- [ ] Database backups tested
- [ ] Documented all passwords

---

## Getting Help

If you encounter issues not covered here:

1. **Check logs:**
   ```bash
   docker-compose logs --tail=100
   ```

2. **Check documentation:**
   - `TROUBLESHOOTING.md` - Detailed troubleshooting guide
   - `SSH-SETUP-GUIDE.md` - SSH key setup
   - `GIT-WORKFLOW-GUIDE.md` - Git workflow

3. **Get system info:**
   ```bash
   docker version
   docker-compose version
   df -h
   free -h
   ```

---

## Version History

- **v1.0** (March 17, 2026) - Initial release based on production deployment
- Tested Odoo image: `odoo:18.0@sha256:f943845750728960f9c3891a7076a72bd257f5b2d50d1c3d993e29a6e06d9489`
- Tested on: Ubuntu 24.04, Docker 27.x, PostgreSQL 16
