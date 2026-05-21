# Deployment Troubleshooting Guide

**Real-world issues encountered during setup and their solutions.**

*Last updated: March 2026*

---

## Table of Contents
1. [Permission Denied Accessing Directories](#1-permission-denied-accessing-directories)
2. [Scripts Requiring Root Access](#2-scripts-requiring-root-access)
3. [Docker Compose Command Not Found](#3-docker-compose-command-not-found)
4. [Docker Permission Denied Errors](#4-docker-permission-denied-errors)
5. [Git Pull Conflicts](#5-git-pull-conflicts)
6. [System Updates and Kernel Upgrades](#6-system-updates-and-kernel-upgrades)

---

## 1. Permission Denied Accessing Directories

### Problem
```bash
odoo-user@ubuntu-erp:~$ cd /opt/odoo18/odoo18-custom-addons/scripts
-bash: cd: /opt/odoo18/odoo18-custom-addons/scripts: Permission denied
```

### Cause
The `odoo-user` user doesn't have execute permissions on directories owned by `odoo18` user.

### Solution Options

**Option A: Copy scripts to home directory (Recommended for deployment)**

```bash
# Copy scripts to your home directory
sudo cp -r /opt/odoo18/odoo18-custom-addons/scripts ~/odoo-scripts
sudo chown -R odoo-user:odoo-user ~/odoo-scripts

# Work from there
cd ~/odoo-scripts
```

**Option B: Fix permissions for shared access**

```bash
# Add odoo-user to odoo18 group
sudo usermod -aG odoo18 odoo-user

# Log out and back in for group changes to take effect
exit
# Reconnect via SSH

# Fix directory permissions
sudo chmod 755 /opt/odoo18
sudo chmod 755 /opt/odoo18/odoo18-custom-addons
sudo chmod 755 /opt/odoo18/odoo18-custom-addons/scripts
```

**Option C: Use sudo for everything**

```bash
sudo -i
cd /opt/odoo18/odoo18-custom-addons/scripts
```

---

## 2. Scripts Requiring Root Access

### Problem
```bash
./00-swap-system-setup.sh
[ERROR] This script must be run as root or with sudo
```

### Cause
System-level operations (swap, Docker installation, etc.) require root privileges.

### Solution
Always run infrastructure scripts with sudo:

```bash
sudo ./00-swap-system-setup.sh
sudo ./01-install-docker.sh
sudo ./03-setup-caddy.sh
```

**Scripts that DON'T need sudo:**
- `02-generate-odoo-stack.sh` (creates files in your home directory)
- `04-setup-oca-modules.sh` (downloads to your home directory)
- `05-deploy.sh` (git operations only)

---

## 3. Docker Compose Command Not Found

### Problem
```bash
docker compose up -d
unknown shorthand flag: 'd' in -d
```

### Cause
Docker Compose plugin is not installed or wrong command syntax.

### Solutions

**Check what's installed:**

```bash
# Search for docker-compose packages
apt search docker-compose

# Check version of old syntax
docker-compose --version

# Check if plugin exists
docker compose version
```

**Install the appropriate version:**

```bash
# Option A: Install docker-compose plugin (newer syntax: "docker compose")
sudo apt update
sudo apt install docker-compose-plugin -y

# Option B: Install docker-compose standalone (older syntax: "docker-compose")
sudo apt install docker-compose -y

# Option C: Install v2 manually
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

**Use the correct syntax:**

```bash
# With plugin
docker compose up -d

# With standalone
docker-compose up -d
```

---

## 4. Docker Permission Denied Errors

### Problem
```bash
docker-compose up -d
PermissionError: [Errno 13] Permission denied
```

### Cause
User is not in the `docker` group and can't access Docker daemon socket.

### Solutions

**Option A: Add user to docker group (Recommended)**

```bash
# Add your user to docker group
sudo usermod -aG docker odoo-user

# Log out and back in for group change to take effect
exit
# SSH back in

# Verify groups
groups
# Should include "docker"

# Now run without sudo
docker-compose up -d
```

**Option B: Quick fix without logging out**

```bash
# Force group refresh for current session
newgrp docker

# Now run docker commands
docker-compose up -d
```

**Option C: Use sudo (temporary)**

```bash
sudo docker-compose up -d
```

---

## 5. Git Pull Conflicts

### Problem
```bash
git pull
error: Your local changes to the following files would be overwritten by merge:
    README.md
Please commit your changes or stash them before you merge.
Aborting
```

### Cause
Local changes conflict with remote repository.

### Solutions

**Option A: Commit local changes**

```bash
# Commit your changes
git add README.md
git commit -m "Update README"
git pull
```

**Option B: Stash changes temporarily**

```bash
# Stash changes
git stash

# Pull from remote
git pull

# Reapply changes later if needed
git stash pop
```

**Option C: Discard local changes**

```bash
# Discard specific file
git checkout README.md
git pull

# Or reset everything to match remote
git fetch origin
git reset --hard origin/main
```

---

## 6. System Updates and Kernel Upgrades

### Problem
```bash
sudo apt upgrade
Pending kernel upgrade!
Running kernel version: 6.8.0-90-generic
Expected kernel version: 6.8.0-106-generic
Restarting the system to load the new kernel will not be handled automatically
```

### Cause
Kernel was updated and system needs reboot to load it.

---

## 7. Odoo Addons Path Not Found

### Problem
```bash
docker-compose up -d
odoo server: error: option --addons-path: the path '/mnt/addons/oca' is not a valid addons directory
```

### Cause
The docker-compose.yml expects addons in `./addons/` relative to where docker-compose runs, but the script created them in a different location. Also, directories may be owned by root if script was run with sudo.

### Solutions

**Option A: Fix ownership and create symlinks manually**

```bash
# Fix ownership
sudo chown -R $USER:$USER ~/addons

# Remove incorrectly placed directories (if they exist)
sudo rm -rf ~/docker/test/addons/oca
sudo rm -rf ~/docker/test/addons/cybrosys
sudo rm -rf ~/docker/test/addons/custom

# Create symlinks
cd ~/docker/test
ln -s ~/addons/oca addons/oca
ln -s ~/addons/cybrosys addons/cybrosys
ln -s ~/addons/custom addons/custom

# Verify
ls -la addons/

# Restart Odoo
docker-compose down
docker-compose up -d
```

**Option B: Regenerate with fixed script**

The script has been updated to automatically create symlinks. Commit and pull the latest version:

```bash
# On your local machine
git add scripts/02-generate-odoo-stack.sh
git commit -m "Fix: Auto-create addons symlinks for docker-compose"
git push

# On droplet
cd /opt/odoo18/odoo18-custom-addons
git pull

# Regenerate the stack
~/odoo-scripts/02-generate-odoo-stack.sh --environment test
```

**Prevention for future deployments:**

When running the setup script, don't use sudo (unless required):

```bash
# Correct - script doesn't need sudo
~/odoo-scripts/02-generate-odoo-stack.sh --environment test

# Incorrect - creates files with root ownership
sudo ~/odoo-scripts/02-generate-odoo-stack.sh --environment test
```

---

## 8. Odoo Sessions Volume Permission Error

### Problem
```bash
AssertionError: /var/lib/odoo/sessions: directory is not writable
```

### Cause
The sessions volume has incorrect permissions, preventing Odoo from writing session data.

### Solution

**Option A: Remove sessions volume (Recommended)**

The sessions volume is not critical for most use cases. Odoo will use in-memory sessions without it.

Edit `docker-compose.yml` and remove:
```yaml
# From volumes section, remove:
- odoo-sessions:/var/lib/odoo/sessions

# From volumes section at bottom, remove:
odoo-sessions:
  name: odoo-test-sessions
```

Then recreate:
```bash
docker-compose down
docker volume rm odoo-test-sessions
docker-compose up -d
```

**Option B: Fix permissions**

```bash
# Fix permissions in the volume
docker run --rm -v odoo-test-sessions:/data alpine sh -c "chmod -R 777 /data"

# Restart
docker-compose restart
```

### Prevention

The updated script (v1.1+) has removed the sessions volume by default. If you need persistent sessions across container restarts, ensure proper permissions are set.

---

## 9. Odoo Addons Path Errors (Empty Directories)

### Problem
```bash
odoo server: error: option --addons-path: the path '/mnt/addons/oca' is not a valid addons directory
```

### Cause
Odoo requires actual valid Odoo modules in the addons directories. Empty directories (even with `__init__.py`) are rejected.

### Solution

**Option A: Comment out addons-path until modules are added**

Edit `docker-compose.yml` command section:
```yaml
command: --
  --data-dir=/var/lib/odoo
  --http-interface=0.0.0.0
  --http-port=8069
  --proxy-mode
  --without-demo=all
  # Uncomment AFTER adding modules:
  # --addons-path=/mnt/addons/oca,/mnt/addons/cybrosys,/mnt/addons/custom
  --db-filter=^${POSTGRES_DB:-${ENVIRONMENT}}$$
```

Also comment out the volume mounts:
```yaml
volumes:
  - odoo-filestore:/var/lib/odoo/filestore
  # Uncomment after adding modules:
  # - ./addons/oca:/mnt/addons/oca:ro
  # - ./addons/cybrosys:/mnt/addons/cybrosys:ro
  # - ./addons/custom:/mnt/addons/custom:ro
```

**Option B: Add actual modules**

```bash
# Install OCA modules
~/odoo-scripts/04-setup-oca-modules.sh

# Move Cybrosys modules
mv base_accounting_kit ~/addons/cybrosys/
mv base_account_budget ~/addons/cybrosys/

# Then uncomment addons-path and volume mounts in docker-compose.yml
# Restart
docker-compose down
docker-compose up -d
```

### Prevention

The updated script (v1.1+) generates docker-compose.yml with addons paths commented out by default. Uncomment them only after adding actual modules to the directories.

---

## 10. --proxy-mode Option Does Not Take a Value

### Problem
```bash
odoo server: error: --proxy-mode option does not take a value
```

### Cause
The `--proxy-mode` flag should not have `=true` appended. It's a boolean flag, not a parameter with a value.

### Solution

Edit `docker-compose.yml` command section:
```yaml
# WRONG:
--proxy-mode=true

# CORRECT:
--proxy-mode
```

### Prevention

The updated script (v1.1+) uses the correct syntax without `=true`.

---

### Solutions

**For Test Environment:**

```bash
# Safe to reboot anytime
sudo reboot

# Reconnect after reboot
ssh odoo-user@your-droplet-ip
```

**For Production Environment:**

```bash
# 1. Schedule maintenance window (low traffic time)
# 2. Create backup BEFORE rebooting
sudo ~/odoo-scripts/backup-odoo.sh backup --environment prod

# 3. Stop services
sudo systemctl stop odoo-prod
sudo systemctl stop caddy

# 4. Reboot
sudo reboot

# 5. After reboot, verify services
sudo systemctl status odoo-prod
sudo systemctl status caddy
curl https://prod.example.com
```

**Disable automatic updates (recommended for production):**

```bash
# Stop automatic update timers
sudo systemctl stop apt-daily.timer
sudo systemctl disable apt-daily.timer
sudo systemctl stop apt-daily-upgrade.timer
sudo systemctl disable apt-daily-upgrade.timer

# Install unattended-upgrades for security patches only
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades
```

---

## Quick Reference: Common Commands

### Check User Permissions
```bash
# Current user
whoami

# User groups
groups

# Check directory permissions
ls -la /path/to/directory

# Check file ownership
ls -l /path/to/file
```

### Fix Docker Issues
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Refresh groups without logout
newgrp docker

# Check Docker status
sudo systemctl status docker

# Check Docker version
docker --version
docker-compose --version
docker compose version
```

### Fix Git Issues
```bash
# Check git status
git status

# Discard local changes
git checkout FILENAME

# Reset to remote
git fetch origin
git reset --hard origin/main

# Stash changes
git stash
git stash pop
```

### System Updates
```bash
# Check what can be upgraded
apt list --upgradable

# Check if reboot is required
cat /var/run/reboot-required

# Update packages
sudo apt update
sudo apt upgrade -y

# Reboot safely (production)
sudo ~/odoo-scripts/backup-odoo.sh backup --environment prod
sudo systemctl stop odoo-prod
sudo reboot
```

---

## Prevention: Initial Setup Checklist

When setting up a new droplet, do these steps first:

### 1. Create Working Directory
```bash
# Copy scripts to home directory
sudo cp -r /opt/odoo18/odoo18-custom-addons/scripts ~/odoo-scripts
sudo chown -R $USER:$USER ~/odoo-scripts
cd ~/odoo-scripts
```

### 2. Add User to Docker Group
```bash
sudo usermod -aG docker $USER
exit
# Reconnect via SSH
```

### 3. Verify Permissions
```bash
# Check you're in docker group
groups | grep docker

# Test Docker access
docker ps
```

### 4. Configure Automatic Updates
```bash
# Disable automatic updates
sudo systemctl stop apt-daily.timer apt-daily-upgrade.timer
sudo systemctl disable apt-daily.timer apt-daily-upgrade.timer

# Enable security updates only
sudo apt install unattended-upgrades -y
```

### 5. Set Up Backup Automation
```bash
# Add to crontab
crontab -e

# Add these lines:
# Daily backup at 2 AM
0 2 * * * /home/odoo-user/odoo-scripts/backup-odoo.sh backup --environment test

# Weekly cleanup on Sunday at 3 AM
0 3 * * 0 /home/odoo-user/odoo-scripts/backup-odoo.sh clean --environment test --retention 7
```

---

## Getting Help

If you encounter an issue not documented here:

1. **Check script logs:**
   ```bash
   journalctl -u docker -n 50
   docker-compose logs --tail=50
   ```

2. **Check system logs:**
   ```bash
   sudo journalctl -xe
   dmesg | tail
   ```

3. **Verify configuration:**
   ```bash
   # Check Docker
   docker info
   docker ps

   # Check services
   systemctl status docker
   systemctl status odoo18
   ```

4. **Review documentation:**
   ```bash
   # Script help
   ./script-name.sh --help

   # README files
   cat ~/odoo-scripts/README.md
   ```

---

## Notes for Future Deployments

**Always do this first on new droplets:**

1. Copy scripts to home directory (don't work in `/opt/odoo18/`)
2. Add user to docker group
3. Log out and back in
4. Run infrastructure scripts with sudo
5. Run application scripts without sudo

**User management:**
- `odoo-user` = admin user with sudo access
- `odoo18` = Odoo service user (for bare-metal)
- `odoo-prod` = Production Odoo user (for bare-metal)
- Docker containers run as root (inside container)

**File locations:**
- Scripts: `~/odoo-scripts/` (your home directory)
- Docker stacks: `~/docker/test/` and `~/docker/prod/`
- Addons: `~/addons/`
- Bare-metal: `/opt/odoo18/` and `/opt/odoo-prod/`

---

## 11. Database Auto-Creation Issue (POSTGRES_DB)

### Problem
```bash
# When clicking "Create database" in browser:
# Error: "database test already exists"

# But database list shows no databases, or database exists but is empty
```

### Cause
Setting `POSTGRES_DB` in docker-compose.yml environment variables causes PostgreSQL to auto-create an empty database shell when the container starts. Odoo then sees this database and refuses to create it, but the empty database is not usable.

### Solution

**Edit docker-compose.yml and remove POSTGRES_DB:**

```yaml
# In the db service environment section:
environment:
  POSTGRES_USER: ${POSTGRES_USER:-odoo}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-changeme}
  # POSTGRES_DB: ${POSTGRES_DB:-test}  # COMMENT THIS OUT OR DELETE
  PGDATA: /var/lib/postgresql/data/pgdata
```

**Then recreate the database:**

```bash
# Drop any existing empty databases
docker-compose exec db psql -U odoo -d postgres -c "DROP DATABASE test;"

# Remove database volume and restart
docker-compose down
docker volume rm odoo-test-db-data
docker-compose up -d
```

### Prevention
Never set `POSTGRES_DB` in docker-compose.yml. Let Odoo create its own databases when needed through the UI or API.

---

## 12. Filestore Permission Denied Error

### Problem
```bash
2026-03-17 00:48:45,573 1 ERROR None odoo.service.db: CREATE DATABASE failed:
PermissionError: [Errno 13] Permission denied: '/var/lib/odoo/filestore/test'
```

### Cause
The filestore volume is created with wrong permissions (owned by root on host). When Odoo container tries to write to it as user `odoo` (UID 101), access is denied.

### Solution

**After first docker-compose up -d, fix permissions immediately:**

```bash
# Wait for containers to be ready
sleep 15

# Fix filestore ownership
docker exec --user root odoo-test chown -R odoo:odoo /var/lib/odoo/filestore

# Verify
docker exec odoo-test ls -la /var/lib/odoo/
```

**Or use a one-liner:**
```bash
docker-compose up -d && sleep 15 && docker exec --user root odoo-test chown -R odoo:odoo /var/lib/odoo/filestore
```

### Prevention

Add this to your deployment checklist - always fix filestore permissions after first container start.

**For automation, add to docker-compose.yml entrypoint:**
```yaml
odoo:
  image: odoo:18.0
  entrypoint: ["/bin/bash", "-c", "chown -R odoo:odoo /var/lib/odoo/filestore && exec /entrypoint.sh"]
  # ... rest of config
```

---

## 13. Odoo Image ir_model Bug (Database Creation Failure)

### Problem
```bash
Database creation error: relation "ir_model" does not exist
LINE 1: SELECT *, name->>'en_US' AS name FROM ir_model WHERE state = 'manual'
```

### Cause
Some Odoo 18.0 Docker images have a regression bug where the base module tries to query the `ir_model` table before creating it during database initialization. This affects builds from late February 2026 onwards.

### Affected Images (Known Bad)
- `odoo:18.0-20260217` (some digests)
- `odoo:18.0-20260119`
- `odoo:18.0` (floating tag, pulls latest which may be buggy)

### Working Images (Tested)
- `odoo:18.0@sha256:f943845750728960f9c3891a7076a72bd257f5b2d50d1c3d993e29a6e06d9489` (Feb 17, 2026 build)

### Solution

**Option A: Use Digest-Pinned Working Image**

```yaml
# In docker-compose.yml
services:
  odoo:
    image: odoo:18.0@sha256:f943845750728960f9c3891a7076a72bd257f5b2d50d1c3d993e29a6e06d9489
```

**Option B: Find Working Image from Local Setup**

If you have a working Podman/Docker setup locally:

```bash
# On local machine (Fedora with Podman)
podman image inspect docker.io/library/odoo:18.0 | grep -E "Created|Digest"

# Use that exact digest on droplet
```

**Option C: Test Different Image Tags**

```bash
# Try older tags
docker pull odoo:18.0-20251215
docker pull odoo:18.0-20251115
# Test each until you find one that works
```

### Prevention
Always pin to specific tested digests, never use floating tags like `odoo:18.0`. Test all images in development environment before production use.

---

## 14. Finding the Correct Odoo Image Digest

### Problem
You need to find which Odoo image digest works, but Docker Hub doesn't show all digests easily.

### Solution

**From a working Podman setup (Fedora laptop):**

```bash
# 1. List Odoo images
podman images | grep odoo

# 2. Get detailed info
podman image inspect docker.io/library/odoo:18.0 | grep -E "Created|Digest"

# 3. Note the Digest and Created date
# Digest: sha256:f943845750728960f9c3891a7076a72bd257f5b2d50d1c3d993e29a6e06d9489
# Created: 2026-02-17T20:31:42.311630332Z
```

**From Docker on droplet:**

```bash
# 1. Pull image to inspect
docker pull odoo:18.0-20260217

# 2. Get digest
docker image inspect odoo:18.0-20260217 | grep Digest

# 3. Use in docker-compose.yml
```

**Best practice: Always use digest in production:**

```yaml
# GOOD - Pinned to specific digest
image: odoo:18.0@sha256:f943845750728960f9c3891a7076a72bd257f5b2d50d1c3d993e29a6e06d9489

# BAD - Floating tag (may change)
image: odoo:18.0

# RISKY - Date tag (may have bugs)
image: odoo:18.0-20260217
```

---

## 15. Podman vs Docker Differences

### Problem
Configuration that works on Fedora with Podman doesn't work on Ubuntu with Docker.

### Key Differences

**Rootless vs Rootful:**
- **Podman:** Rootless by default, runs as your user
- **Docker:** Runs as root via daemon, requires sudo or group membership

**Permission Handling:**
- **Podman:** Uses your user's UID/GID, no permission issues
- **Docker:** Containers use internal UIDs (101 for odoo), volumes owned by root

**Image Tags:**
- **Podman:** Can use same tags as Docker (same registries)
- **Docker:** Same tags, but digest matching is critical

**Commands:**
- **Podman:** `podman-compose` or `podman compose`
- **Docker:** `docker-compose` or `docker compose`

### Solution for Migration

**When moving from Podman (local) to Docker (production):**

1. **Get exact image digest from local:**
   ```bash
   podman image inspect odoo:18.0 | grep Digest
   ```

2. **Use that digest in Docker:**
   ```yaml
   image: odoo:18.0@sha256:...digest...
   ```

3. **Add permission fix for volumes:**
   ```bash
   docker exec --user root <container> chown -R odoo:odoo /var/lib/odoo/filestore
   ```

4. **Comment out POSTGRES_DB** (Podman may handle this differently)

5. **Test thoroughly** before production use

---

## Changelog

- **March 17, 2026**: Added sections 11-15 covering database auto-creation, filestore permissions, ir_model bug, image digests, and Podman vs Docker differences
- **March 2026**: Initial troubleshooting guide based on first deployment issues
