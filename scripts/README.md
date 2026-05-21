# Odoo on Docker — Deployment Scripts

Complete automation suite for deploying Odoo 18 on Docker across multiple customers. Designed for scalability, reusability, and production reliability.

## Overview

A comprehensive collection of automation scripts that handle the complete lifecycle of Odoo deployments:

**Infrastructure Scripts:**
- System preparation (swap, limits)
- Docker installation
- Docker Compose stack generation

**Operational Scripts:**
- Caddy reverse proxy configuration
- OCA modules management
- Git-based deployment workflow
- Bare-metal to Docker migration

**Monitoring & Maintenance:**
- Health check and monitoring
- Backup and restore automation

**Master Deployment:**
- One-command full deployment (`deploy-all.sh`)

**Target deployment:** Ubuntu 24.04 LTS on DigitalOcean droplets

## Quick Start

### Full Deployment (Recommended for New Droplets)

```bash
# One-command deployment
sudo ./scripts/deploy-all.sh --customer myclient --environment test --domain test.example.com
```

### Step-by-Step Deployment

```bash
# 1. System preparation
sudo ./scripts/00-swap-system-setup.sh

# 2. Install Docker
sudo ./scripts/01-install-docker.sh

# 3. Generate Docker Compose stack
./scripts/02-generate-odoo-stack.sh --environment test

# 4. Edit environment variables (IMPORTANT!)
nano docker/test/.env

# 5. Set up OCA modules (optional)
./scripts/04-setup-oca-modules.sh

# 6. Configure Caddy reverse proxy (if you have a domain)
sudo ./scripts/03-setup-caddy.sh --domain test.example.com --port 8069

# 7. Start Odoo
cd docker/test && docker compose up -d
```

## Scripts Index

| # | Script | Purpose | For |
|---|--------|---------|-----|
| 00 | `00-swap-system-setup.sh` | System preparation (swap, limits) | All |
| 01 | `01-install-docker.sh` | Docker Engine + Compose | All |
| 02 | `02-generate-odoo-stack.sh` | Docker Compose configuration | All |
| 03 | `03-setup-caddy.sh` | Caddy reverse proxy | All |
| 04 | `04-setup-oca-modules.sh` | OCA repositories management | All |
| 05 | `05-deploy.sh` | Git-based deployment workflow | All |
| 06 | `06-migrate-to-docker.sh` | Bare-metal to Docker migration | Migration |
| 07 | `07-health-check.sh` | Health monitoring | Ops |
| - | `backup-odoo.sh` | Backup and restore | All |
| - | `deploy-all.sh` | Master deployment script | New Droplets |

---

## Detailed Script Reference

### deploy-all.sh (Master Deployment Script)

**Purpose:** One-command setup for complete Odoo deployment

**What it does:**
- Orchestrates all deployment scripts in sequence
- Configurable with command-line options
- Supports step-by-step execution
- Provides deployment summary

**Usage:**

```bash
# Full deployment for test environment
sudo ./scripts/deploy-all.sh --customer myclient --environment test --domain test.example.com

# Production deployment
sudo ./scripts/deploy-all.sh --environment prod --domain prod.example.com --port 8070

# Run specific step only
sudo ./scripts/deploy-all.sh --step swap
sudo ./scripts/deploy-all.sh --step docker

# Non-interactive deployment
sudo ./scripts/deploy-all.sh --non-interactive --environment test

# Skip specific steps
sudo ./scripts/deploy-all.sh --skip-swap --skip-addons
```

**Options:**
- `-c, --customer NAME` - Customer name (default: myclient)
- `-e, --environment ENV` - Environment: test, prod (default: test)
- `-d, --domain DOMAIN` - Domain name (for Caddy)
- `-p, --port PORT` - Odoo port (default: 8069)
- `-s, --step STEP` - Run specific step only
- `--skip-swap` - Skip swap configuration
- `--skip-docker` - Skip Docker installation
- `--skip-caddy` - Skip Caddy configuration
- `--skip-addons` - Skip OCA modules setup
- `--no-start` - Don't start services
- `--non-interactive` - Run without prompts

---

### 03-setup-caddy.sh (Caddy Reverse Proxy)

**Purpose:** Configure Caddy as reverse proxy with automatic SSL

**What it does:**
- Configures Caddy for Odoo proxy
- Automatic SSL via Let's Encrypt
- Proper headers for OAuth
- WebSocket support

**Usage:**

```bash
# Configure Caddy for test environment
sudo ./scripts/03-setup-caddy.sh --domain test.example.com --port 8069

# Configure for production
sudo ./scripts/03-setup-caddy.sh --domain prod.example.com --port 8070

# Remove configuration
sudo ./scripts/03-setup-caddy.sh --domain test.example.com --remove
```

**Why Caddy instead of Nginx:**
- Automatic SSL (zero manual configuration)
- Proper `X-Forwarded-*` headers for Microsoft 365 OAuth
- Simple, human-readable configuration
- Auto-renewal of certificates

---

### 04-setup-oca-modules.sh (OCA Modules Management)

**Purpose:** Clone and configure OCA community modules

**What it does:**
- Clones OCA repositories from GitHub
- Checks out appropriate branches
- Manages module updates
- Lists available repositories

**Usage:**

```bash
# Install default OCA repos
./scripts/04-setup-oca-modules.sh

# Install specific repos
./scripts/04-setup-oca-modules.sh --repos "social server-tools web"

# List available OCA repositories
./scripts/04-setup-oca-modules.sh --list

# Update existing repos
./scripts/04-setup-oca-modules.sh --update

# Use SSH instead of HTTPS
./scripts/04-setup-oca-modules.sh --ssh

# Install for different Odoo version
./scripts/04-setup-oca-modules.sh --version 17.0
```

**Default repositories:**
- `social` - WhatsApp, Telegram integration
- `account-financial-tools` - Accounting enhancements
- `reporting-engine` - Custom report generation

---

### 05-deploy.sh (Git-Based Deployment Workflow)

**Purpose:** Automate git pull + service restart workflow

**What it does:**
- Pulls latest changes from git
- Shows deployment diff
- Restarts services (Docker or bare-metal)
- Runs health checks

**Usage:**

```bash
# Deploy to test environment
./scripts/05-deploy.sh --environment test

# Deploy specific branch
./scripts/05-deploy.sh --environment prod --branch feature/new-module

# Dry run (show what would change)
./scripts/05-deploy.sh --environment test --dry-run

# Deploy without automatic restart
./scripts/05-deploy.sh --environment test --no-restart
```

**Workflow:**
1. Pre-deployment checks (uncommitted changes)
2. Optional backup
3. Pull latest changes
4. Show commit diff
5. Restart service
6. Health check
7. Deployment summary

---

### 06-migrate-to-docker.sh (Bare-Metal to Docker Migration)

**Purpose:** Migrate existing bare-metal Odoo to Docker

**What it does:**
- Backs up bare-metal data
- Starts Docker containers
- Restores data to Docker
- Validates migration
- Keeps bare-metal as fallback

**Usage:**

```bash
# Migrate test environment
sudo ./scripts/06-migrate-to-docker.sh --environment test

# Migrate production
sudo ./scripts/06-migrate-to-docker.sh --environment prod

# Keep bare-metal running during migration
sudo ./scripts/06-migrate-to-docker.sh --environment test --keep-bare-metal-running
```

**Safety features:**
- Bare-metal remains intact (fallback)
- Complete backup before migration
- Post-migration validation
- Detailed logging
- Rollback capability

---

### 07-health-check.sh (Health Monitoring)

**Purpose:** Monitor Odoo instances and provide health diagnostics

**What it does:**
- Checks system resources (CPU, RAM, disk)
- Monitors Docker containers/services
- Verifies HTTP endpoints
- Scans logs for errors
- Sends alerts (optional)

**Usage:**

```bash
# Check all environments
./scripts/07-health-check.sh

# Check specific environment
./scripts/07-health-check.sh --environment test

# JSON output for monitoring tools
./scripts/07-health-check.sh --output json

# With custom thresholds and email alerts
./scripts/07-health-check.sh --cpu-warning 60 --disk-critical 85 --email admin@example.com
```

**Automation (crontab):**

```bash
# Every 5 minutes with email alerts
*/5 * * * * /path/to/07-health-check.sh --email admin@example.com

# Every hour with JSON output
0 * * * * /path/to/07-health-check.sh --output json > /var/log/odoo-health.json
```

**Thresholds:**
- CPU: Warning 70%, Critical 90%
- RAM: Warning 70%, Critical 85%
- Disk: Warning 80%, Critical 90%

---

## Environment Variables Reference

### Global Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `ENVIRONMENT` | Environment name | test |
| `PROJECT_NAME` | Docker Compose project name | odoo |
| `BACKUP_DIR` | Backup directory | /var/backups/odoo |
| `RETENTION_DAYS` | Backup retention | 7 |

### System Configuration

| Variable | Purpose | Default |
|----------|---------|---------|
| `SWAP_SIZE_GB` | Swap size in GB | 2 |
| `SWAPPINESS` | Swap tendency (1-100) | 10 |

### Docker Configuration

| Variable | Purpose | Default |
|----------|---------|---------|
| `DOCKER_USER` | User to add to docker group | auto-detect |
| `COMPOSE_PROJECT_NAME` | Docker Compose project name | odoo |

### Odoo Configuration

| Variable | Purpose | Default |
|----------|---------|---------|
| `ODOO_VERSION` | Odoo version | 18.0 |
| `POSTGRES_VERSION` | PostgreSQL version | 16 |
| `ODOO_PORT` | Odoo port | 8069 |

## Post-Installation Steps

### 1. Configure Environment Variables

```bash
nano docker/test/.env
```

**Important:** Set secure passwords!

```bash
COMPOSE_PROJECT_NAME=odoo
POSTGRES_USER=odoo
POSTGRES_PASSWORD=$(openssl rand -base64 32)
POSTGRES_DB=test
ODOO_ADMIN_PASSWORD=$(openssl rand -base64 32)
```

### 2. Set Up Addons

#### OCA Modules:

```bash
./scripts/04-setup-oca-modules.sh
```

#### Cybrosys Modules:

```bash
mv base_accounting_kit addons/cybrosys/
mv base_account_budget addons/cybrosys/
```

### 3. Access Odoo

- **URL:** `https://your-domain.com` or `http://your-ip:8069`
- **First run:** Create database
- **Master password:** Set `ODOO_MASTER_PASSWORD` in `.env`

### 4. Set Up Automated Backups

```bash
# Add to crontab
crontab -e

# Daily backup at 2 AM
0 2 * * * /path/to/scripts/backup-odoo.sh backup --environment test

# Weekly cleanup on Sunday at 3 AM
0 3 * * 0 /path/to/scripts/backup-odoo.sh clean --environment test --retention 7
```

### 5. Set Up Health Monitoring

```bash
# Add to crontab
crontab -e

# Every 5 minutes
*/5 * * * * /path/to/scripts/07-health-check.sh --environment test
```

## Troubleshooting

### System Issues

**Swap not working:**

```bash
sudo swapon --show
free -h
cat /proc/sys/vm/swappiness
```

**Docker service not running:**

```bash
sudo systemctl status docker
sudo journalctl -u docker -n 50
```

### Odoo Issues

**Container not starting:**

```bash
cd docker/test
docker compose logs odoo
docker compose ps
docker compose restart
```

**Database connection errors:**

Check `.env` file matches:
- `POSTGRES_USER` and `POSTGRES_PASSWORD`
- `POSTGRES_DB` is the database name

### Permission Issues

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in
```

## Best Practices

### Security

1. **Never commit `.env` files** - Add to `.gitignore`
2. **Use strong passwords** - `openssl rand -base64 32`
3. **Update regularly** - Keep Docker and Odoo images updated
4. **Limit exposure** - Use Caddy reverse proxy + UFW firewall
5. **Rotate credentials** - Change passwords periodically

### Backups

1. **Test restores regularly** - Don't wait for disaster
2. **Off-site backups** - Use rsync/rclone for remote sync
3. **Retention policy** - Keep 7-30 days based on disk space
4. **Encrypt backups** - Use `--encrypt` flag for sensitive data
5. **Document restore process** - Know how to recover quickly

### Monitoring

1. **Monitor resources** - CPU, RAM, disk usage alerts
2. **Review logs** - Check for errors regularly
3. **Database growth** - Monitor and plan capacity
4. **Health checks** - Automated monitoring with alerts
5. **Performance metrics** - Track response times

### Deployment

1. **Test first** - Always test on test environment
2. **Backup before deploy** - Automatic via `05-deploy.sh`
3. **Document changes** - Commit messages should be clear
4. **Rollback plan** - Know how to revert if needed
5. **Monitor after deploy** - Check logs and health

## Multi-Customer Deployment

### Directory Structure

```
customers/
├── myclient/
│   └── odoo-deployment-stack/
├── hotel2/
│   └── odoo-hotel2/
└── hotel3/
    └── odoo-hotel3/
```

### Customer Configuration Template

Create `customer-config.sh`:

```bash
#!/bin/bash
# Customer: MyClient Hotel
export CUSTOMER_NAME=myclient
export ENVIRONMENT=test
export PROJECT_NAME=myclient-odoo
export ODOO_PORT=8069
export BACKUP_DIR=/var/backups/odoo/myclient
export RETENTION_DAYS=14
```

Use with scripts:

```bash
source customer-config.sh
./scripts/backup-odoo.sh backup --environment $ENVIRONMENT
```

## Roadmap

### Planned Enhancements

- [ ] Automated SSL certificate monitoring
- [ ] Performance benchmarking script
- [ ] Multi-database deployment support
- [ ] Automated update testing
- [ ] Disaster recovery runbook generator
- [ ] Customer onboarding wizard
- [ ] Centralized monitoring dashboard
- [ ] Automated security scanning

### Future Scripts

- `09-update-odoo.sh` - Automated Odoo version updates
- `10-scale-helpers.sh` - Scaling and load balancing
- `11-security-hardening.sh` - Security best practices

## Changelog

### Version 2.0 (March 2026)
- Added Caddy reverse proxy automation
- Added OCA modules management
- Added git-based deployment workflow
- Added bare-metal to Docker migration
- Added health check and monitoring
- Added master deployment script
- Improved error handling and logging
- Better multi-customer support

### Version 1.0 (March 2026)
- Initial release
- Swap configuration
- Docker installation
- Docker Compose stack generation
- Backup and restore automation
- Multi-environment support

## Support

For issues or improvements:

1. Check troubleshooting section
2. Review script logs: `journalctl -u docker`
3. Test on test environment first
4. Document customer-specific requirements

## License

These scripts are part of the odoo-deployment-stack project.
