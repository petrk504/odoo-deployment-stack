# Odoo 18 Docker Deployment Guide

**Complete step-by-step guide for deploying Odoo 18 on Docker.**

*Customer: Client Company / MyClient Hotel*
*Last Updated: March 17, 2026*

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Server Setup](#initial-server-setup)
3. [Docker Installation](#docker-installation)
4. [Getting the Working Odoo Image](#getting-the-working-odoo-image)
5. [Deploying Test Environment](#deploying-test-environment)
6. [Deploying Production Environment](#deploying-production-environment)
7. [Post-Deployment Configuration](#post-deployment-configuration)
8. [Backup Strategy](#backup-strategy)
9. [Troubleshooting](#troubleshooting)
10. [Maintenance](#maintenance)

---

## Prerequisites

### Requirements
- **Server:** Ubuntu 24.04 LTS (DigitalOcean droplet or equivalent)
- **RAM:** 4GB minimum (3.8GB tested and working)
- **Storage:** 50GB+ SSD
- **Network:** Public IP with domain configured
- **Local:** Fedora laptop with Podman (for testing images)

### Before You Begin

1. **Server Access:**
   - SSH access with sudo privileges
   - User: `odoo-user` (or your admin user)

2. **Domain Configuration:**
   - Test domain: `test.example.com`
   - Production domain: `prod.example.com`
   - DNS pointing to server IP

3. **Local Setup (Fedora):**
   - Podman installed
   - Working Odoo 18 image available
   - Git repository cloned

---

## Initial Server Setup

### Step 1: Create Swap (Safety Net)

```bash
# Create 2GB swap file
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Set swappiness (use swap only when necessary)
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

# Verify
free -h
swapon --show
```

### Step 2: Create Directory Structure

```bash
# Create main directories
mkdir -p ~/docker/{test,prod}
mkdir -p ~/addons/{custom,oca,cybrosys}
mkdir -p ~/backups/scripts
mkdir -p ~/odoo-scripts

# Fix ownership
sudo chown -R $USER:$USER ~/docker ~/addons ~/backups ~/odoo-scripts

# Verify
ls -la ~ | grep -E "docker|addons|backups|odoo-scripts"
```

### Step 3: Add User to Docker Group

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in OR use:
newgrp docker

# Verify
groups | grep docker
```

---

## Docker Installation

```bash
# Update packages
sudo apt update
sudo apt upgrade -y

# Install Docker
sudo apt install -y docker.io docker-compose

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Verify installation
docker --version
docker-compose --version

# Test without sudo (if group membership worked)
docker ps
```

**If docker ps fails with permission denied:**
```bash
# You need to log out and back in
exit
# SSH back in
```

---

## Getting the Working Odoo Image

### From Local Podman Setup (Fedora Laptop)

```bash
# On your Fedora laptop
podman images | grep odoo

# Get the digest of the working image
podman image inspect docker.io/library/odoo:18.0 | grep -E "Created|Digest"

# Example output:
# Digest: sha256:f943845750728960f9c3891a7076a72bd257f5b2d50d1c3d993e29a6e06d9489
# Created: 2026-02-17T20:31:42.311630332Z

# SAVE THIS DIGEST - you'll need it for the droplet
```

### On the Droplet

```bash
# No need to pull - docker-compose will pull the image by digest
# Just verify the digest is ready to use
```

---

## Deploying Test Environment

### Step 1: Create docker-compose.yml

```bash
cd ~/docker/test
nano docker-compose.yml
```

**Paste this complete configuration:**

```yaml
# Docker Compose configuration for Odoo 18.0
# Environment: test
# Customer: MyClient Hotel
#
# VERSION PINNING: Using tested working image
# Image: odoo:18.0@sha256:f943845750728960f9c3891a7076a72bd257f5b2d50d1c3d993e29a6e06d9489
# Created: 2026-02-17 (tested on Fedora laptop with Podman)
#
# PERMISSION SETUP:
# After first run, execute: sudo docker exec --user root odoo-test chown -R odoo:odoo /var/lib/odoo/filestore

services:
  db:
    image: postgres:16
    container_name: ${COMPOSE_PROJECT_NAME:-odoo}-test-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-odoo}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-changeme}
      # POSTGRES_DB: ${POSTGRES_DB:-test}  # NEVER set this - causes empty database creation
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - odoo-db-data:/var/lib/postgresql/data/pgdata
    networks:
      - odoo-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-odoo}"]
      interval: 10s
      timeout: 5s
      retries: 5

  odoo:
    image: odoo:18.0@sha256:f943845750728960f9c3891a7076a72bd257f5b2d50d1c3d993e29a6e06d9489
    container_name: ${COMPOSE_PROJECT_NAME:-odoo}-test
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "${ODOO_PORT:-8069}:8069"
    environment:
      HOST: db
      PORT: 5432
      USER: ${POSTGRES_USER:-odoo}
      PASSWORD: ${POSTGRES_PASSWORD:-changeme}
      DATABASE: test
      PROXY_MODE: "true"
    volumes:
      - odoo-filestore:/var/lib/odoo/filestore
    networks:
      - odoo-network
    command: --data-dir=/var/lib/odoo --http-interface=0.0.0.0 --http-port=8069 --proxy-mode --without-demo=all --db-filter=^test$$

networks:
  odoo-network:
    driver: bridge
    name: ${COMPOSE_PROJECT_NAME:-odoo}-test-network

volumes:
  odoo-db-data:
    name: ${COMPOSE_PROJECT_NAME:-odoo}-test-db-data
  odoo-filestore:
    name: ${COMPOSE_PROJECT_NAME:-odoo}-test-filestore
```

**Save:** Ctrl+X, Y, Enter

### Step 2: Create .env File

```bash
nano .env
```

**Paste this configuration:**

```bash
# Docker Compose project name
COMPOSE_PROJECT_NAME=odoo

# PostgreSQL Configuration
POSTGRES_USER=odoo
POSTGRES_PASSWORD=CHANGE_THIS_PASSWORD_NOW

# Odoo Configuration
ODOO_PORT=8069

# Database name (for Odoo, NOT for PostgreSQL)
DATABASE=test
```

**Update passwords:** Change `CHANGE_THIS_PASSWORD_NOW` to a secure password

**Save:** Ctrl+X, Y, Enter

### Step 3: Initial Deployment

```bash
# Pull the image (this will download the digest-pinned image)
sudo docker-compose pull

# Start containers
sudo docker-compose up -d

# Wait for containers to be ready (CRITICAL!)
sleep 20

# Fix filestore permissions (CRITICAL - prevents database creation errors)
sudo docker exec --user root odoo-test chown -R odoo:odoo /var/lib/odoo/filestore

# Verify Odoo is running
sudo docker logs --tail=20 odoo-test | grep "HTTP service"

# Should see: HTTP service (werkzeug) running on <container-id>:8069
```

### Step 4: Verify Database Setup

```bash
# Check databases (should only have postgres, template0, template1)
sudo docker-compose exec db psql -U odoo -d postgres -c "\l"

# If you see an "odoo" or "test" database, drop it:
sudo docker-compose exec db psql -U odoo -d postgres -c "DROP DATABASE odoo;"
sudo docker-compose exec db psql -U odoo -d postgres -c "DROP DATABASE test;"
```

### Step 5: Create Database via Browser

1. **Open browser:** `http://test.example.com` or `http://<your-ip>:8069`

2. **Click "Create database"**

3. **Fill in details:**
   - Database name: `test`
   - Email: admin@yourdomain.com
   - Password: (choose secure password)
   - Language: English (or your preference)
   - Country: Your country

4. **Click "Create database"**

5. **Wait for initialization** (1-3 minutes)

6. **You should see the Odoo dashboard!**

---

## Deploying Production Environment

### Step 1: Create Production docker-compose.yml

```bash
cd ~/docker/prod
nano docker-compose.yml
```

**Same as test but with these changes:**

```yaml
# Change container names to prod
container_name: ${COMPOSE_PROJECT_NAME:-odoo}-prod-db
container_name: ${COMPOSE_PROJECT_NAME:-odoo}-prod

# Change volume names
odoo-prod-db-data:
odoo-prod-filestore:

# Change network name
name: ${COMPOSE_PROJECT_NAME:-odoo}-prod-network

# Change port
ports:
  - "${ODOO_PORT:-8070}:8069"  # Production uses 8070

# Change database name
DATABASE: prod

# Change db-filter
--db-filter=^prod$$
```

### Step 2: Create Production .env

```bash
nano .env
```

```bash
COMPOSE_PROJECT_NAME=odoo
POSTGRES_USER=odoo
POSTGRES_PASSWORD=DIFFERENT_SECURE_PASSWORD
ODOO_PORT=8070
DATABASE=prod
```

### Step 3: Deploy Production

```bash
# Start production
sudo docker-compose up -d

# Fix permissions
sleep 20
sudo docker exec --user root odoo-prod chown -R odoo:odoo /var/lib/odoo/filestore

# Create database via browser
# http://prod.example.com
```

---

## Post-Deployment Configuration

### Configure Caddy Reverse Proxy

Caddy is already configured (from bare-metal setup). Just verify it points to Docker:

```bash
# Check Caddy config
sudo cat /etc/caddy/Caddyfile

# Should proxy port 8069 (test) and 8070 (prod)
# Restart Caddy if needed
sudo systemctl restart caddy
```

### Install OCA Modules (Optional)

```bash
# Only after database is created and working!

# Clone OCA modules
cd ~/addons/oca
git clone https://github.com/OCA/social.git
git clone https://github.com/OCA/account-financial-tools.git
git clone https://github.com/OCA/reporting-engine.git

# Checkout 18.0 branch
cd social && git checkout 18.0
cd ../account-financial-tools && git checkout 18.0
cd ../reporting-engine && git checkout 18.0

# Update docker-compose.yml to mount addons
# Uncomment lines in docker-compose.yml:
# volumes:
#   - ./addons/oca:/mnt/addons/oca:ro

# Update command to include addons-path
# Uncomment:
# --addons-path=/mnt/addons/oca

# Restart
sudo docker-compose down
sudo docker-compose up -d
```

### Configure Automatic Backups

See [Backup Strategy](#backup-strategy) section below.

---

## Backup Strategy

### Manual Backup

```bash
# Backup test database
sudo docker-compose exec db pg_dump -U odoo test > ~/backups/test_backup_$(date +%Y%m%d).sql

# Backup filestore
sudo docker run --rm -v odoo-test-filestore:/data -v ~/backups:/backup alpine tar czf /backup/filestore_$(date +%Y%m%d).tar.gz -C /data .
```

### Automated Backup Script

Create `~/backups/scripts/backup.sh`:

```bash
#!/bin/bash
# Backup script for Odoo Docker deployment

BACKUP_DIR=~/backups
ENVIRONMENT=${1:-test}
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p $BACKUP_DIR/$ENVIRONMENT

# Backup database
echo "Backing up $ENVIRONMENT database..."
cd ~/docker/$ENVIRONMENT
docker-compose exec -T db pg_dump -U odoo $ENVIRONMENT > $BACKUP_DIR/$ENVIRONMENT/db_$DATE.sql

# Backup filestore
echo "Backing up $ENVIRONMENT filestore..."
docker run --rm \
  -v odoo-${ENVIRONMENT}-filestore:/data \
  -v $BACKUP_DIR/$ENVIRONMENT:/backup \
  alpine tar czf /backup/filestore_$DATE.tar.gz -C /data .

# Keep last 7 days only
find $BACKUP_DIR/$ENVIRONMENT -name "db_*.sql" -mtime +7 -delete
find $BACKUP_DIR/$ENVIRONMENT -name "filestore_*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
```

**Make it executable:**
```bash
chmod +x ~/backups/scripts/backup.sh
```

**Add to crontab:**
```bash
crontab -e

# Add:
# Daily backup at 2 AM
0 2 * * * ~/backups/scripts/backup.sh test
0 2 * * * ~/backups/scripts/backup.sh prod
```

### Restore from Backup

```bash
# Restore database
cd ~/docker/test
docker-compose exec -T db psql -U odoo test < ~/backups/test/db_20260317_020000.sql

# Restore filestore
docker run --rm \
  -v odoo-test-filestore:/data \
  -v ~/backups/test:/backup \
  alpine tar xzf /backup/filestore_20260317_020000.tar.gz -C /data
```

---

## Troubleshooting

### Common Issues

#### 1. Permission Denied on filestore

```bash
# Symptom: Database creation fails with permission error
# Solution:
sudo docker exec --user root odoo-test chown -R odoo:odoo /var/lib/odoo/filestore
```

#### 2. Database already exists

```bash
# Symptom: Odoo says database exists but PostgreSQL shows it doesn't
# Check for empty databases:
sudo docker-compose exec db psql -U odoo -d postgres -c "\l"

# If found, drop it:
sudo docker-compose exec db psql -U odoo -d postgres -c "DROP DATABASE test;"
```

#### 3. Container won't start (crash-looping)

```bash
# Check logs
sudo docker logs odoo-test --tail=100

# Common causes:
# - Wrong image digest (ir_model bug)
# - Addons path pointing to empty directories
# - Wrong --proxy-mode syntax (should be without =true)
```

#### 4. Can't access via domain

```bash
# Check Caddy status
sudo systemctl status caddy

# Check Caddy logs
sudo journalctl -u caddy -n 50

# Verify port is open
sudo netstat -tlnp | grep 8069
```

### Full Troubleshooting Guide

See `TROUBLESHOOTING-DEPLOYMENT.md` for detailed troubleshooting steps.

---

## Maintenance

### Regular Tasks

**Daily (automated):**
- Backups run at 2 AM

**Weekly:**
- Check disk space: `df -h`
- Check logs: `sudo docker logs odoo-test --tail=100`
- Verify backups: `ls -lh ~/backups/test/`

**Monthly:**
- Review logs for errors
- Test restore from backup
- Check for security updates: `sudo apt list --upgradable`

**Quarterly:**
- Update OCA modules: `cd ~/addons/oca && git pull`
- Review and update documentation
- Plan for capacity upgrades

### Updates

**Updating Odoo Image:**

```bash
# 1. Test on test environment first
# 2. Pull new image digest from working local setup
# 3. Update docker-compose.yml with new digest
# 4. Backup before updating
~/backups/scripts/backup.sh test

# 5. Update
cd ~/docker/test
sudo docker-compose pull
sudo docker-compose down
sudo docker-compose up -d

# 6. Fix permissions
sudo docker exec --user root odoo-test chown -R odoo:odoo /var/lib/odoo/filestore

# 7. Verify everything works
# 8. Only after test passes, update prod
```

**System Updates:**

```bash
# List available updates
sudo apt list --upgradable

# Update packages
sudo apt update
sudo apt upgrade -y

# Check if reboot required
cat /var/run/reboot-required

# If reboot required, schedule maintenance window
# Create backup first
~/backups/scripts/backup.sh prod

# Then reboot
sudo reboot
```

---

## Quick Reference Commands

### Check System Status

```bash
# Check if containers are running
sudo docker ps

# Check Odoo logs
sudo docker logs -f odoo-test

# Check database list
sudo docker-compose exec db psql -U odoo -d postgres -c "\l"

# Check disk space
df -h

# Check memory
free -h
```

### Container Management

```bash
# Stop containers
sudo docker-compose down

# Start containers
sudo docker-compose up -d

# Restart containers
sudo docker-compose restart

# Remove volumes (WARNING: deletes all data)
sudo docker-compose down -v
sudo docker volume rm odoo-test-db-data odoo-test-filestore
```

### Backup and Restore

```bash
# Manual backup
~/backups/scripts/backup.sh test

# List backups
ls -lh ~/backups/test/

# Restore database
sudo docker-compose exec -T db psql -U odoo test < ~/backups/test/db_YYYYMMDD_HHMMSS.sql
```

---

## Security Checklist

- [ ] Strong passwords in .env files
- [ ] .env files not committed to git (in .gitignore)
- [ ] SSH key-based authentication only
- [ ] Firewall configured (ufw)
- [ ] Automatic security updates enabled
- [ ] Regular backups tested
- [ ] SSL certificates valid (Caddy manages this)
- [ ] Odoo admin password changed from default
- [ ] Database master password set and secure
- [ ] Unused ports closed
- [ ] Log monitoring configured

---

## Support and Documentation

### Documentation Files
- `TROUBLESHOOTING-DEPLOYMENT.md` - Detailed troubleshooting guide
- `CLAUDE.md` - Project overview and architecture
- `README.md` - General project information

### Getting Help

1. **Check logs first:**
   ```bash
   sudo docker logs odoo-test --tail=100
   sudo journalctl -xe
   ```

2. **Verify configuration:**
   ```bash
   sudo docker-compose config
   ```

3. **Review troubleshooting guide**

4. **Check Odoo logs:**
   ```bash
   sudo docker exec odoo-test cat /var/log/odoo/odoo.log
   ```

---

## Version History

- **v1.0** (March 17, 2026): Initial deployment guide based on successful test deployment
- Tested on: Ubuntu 24.04, Docker 27.x, Odoo 18.0-20260217
- Image digest: `sha256:f943845750728960f9c3891a7076a72bd257f5b2d50d1c3d993e29a6e06d9489`

---

**Remember: Always test on test environment first!**
