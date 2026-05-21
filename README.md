# Odoo 18 Deployment Stack

Production-grade Odoo 18 deployment on DigitalOcean Ubuntu 24.04, built for a hospitality client. Covers automated installation, dual-instance setup (test + production), OCA module management, automated backups, and operational runbooks.

## Stack

| Component | Choice | Reason |
|:----------|:-------|:-------|
| OS | Ubuntu 24.04 | LTS, well-supported by Odoo |
| Reverse proxy | Caddy | Auto SSL, correct proxy headers out of the box |
| Database | PostgreSQL | Odoo default |
| Process manager | systemd | Reliable, standard |
| OCA modules | Git submodules | Clean version pinning |
| Hosting | DigitalOcean Droplet | Cost-effective, simple to manage |

## Architecture

Two isolated Odoo instances on a single droplet:

```
Internet → Caddy (SSL) → odoo18:8069   (test)
                       → odoo-prod:8070 (production)
```

Each instance has a dedicated system user, PostgreSQL user, virtualenv, config file, and systemd service. No cross-contamination between test and production.

## Repository Structure

```
scripts/
  00-swap-system-setup.sh       # Swap + system tuning
  01-install-docker.sh          # Docker install
  02-generate-odoo-stack.sh     # Core Odoo stack generator
  03-setup-caddy.sh             # Caddy reverse proxy
  04-setup-oca-modules.sh       # OCA module installation
  05-deploy.sh                  # Deployment
  06-migrate-to-docker.sh       # Docker migration path
  07-health-check.sh            # Health monitoring
  backup-odoo.sh                # Automated backups
  deploy-all.sh                 # Full stack deployment
```

## Key Design Decisions

**Caddy over Nginx** — Nginx requires manual `X-Forwarded-Proto` header configuration for OAuth providers (Microsoft 365 Calendar, etc.). Caddy sets correct proxy headers by default, eliminating a common Odoo OAuth failure mode.

**Git-based deployments** — No manual file editing on the server. All changes flow through GitHub and are pulled by the service user.

**Isolated system users** — Each Odoo instance runs as a dedicated unprivileged user (`odoo18`, `odoo-prod`). Limits blast radius of any misconfiguration.

**OCA modules as git submodules** — Version-pinned, auditable, easy to update selectively.

## Documentation

| Document | Description |
|:---------|:------------|
| [PRODUCTION-SETUP.md](./PRODUCTION-SETUP.md) | Full production deployment guide |
| [DOCKER-DEPLOYMENT-GUIDE.md](./DOCKER-DEPLOYMENT-GUIDE.md) | Docker-based deployment |
| [AUTOMATION.md](./AUTOMATION.md) | Automated installation scripts |
| [GIT-WORKFLOW-GUIDE.md](./GIT-WORKFLOW-GUIDE.md) | Git workflow and branching strategy |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Common issues and fixes |
| [TROUBLESHOOTING-DEPLOYMENT.md](./TROUBLESHOOTING-DEPLOYMENT.md) | Deployment-specific troubleshooting |
| [SSH-SETUP-GUIDE.md](./SSH-SETUP-GUIDE.md) | SSH key setup |

## OCA Modules

- `account-financial-tools` — accounting enhancements
- `reporting-engine` — advanced reporting (QWeb/Aeroo)
- `mail_gateway_whatsapp` — WhatsApp messaging gateway *(from OCA `social`; installed at deploy time via `04-setup-oca-modules.sh`, not vendored as a submodule)*

See [EXTERNAL-DEPENDENCIES.txt](./EXTERNAL-DEPENDENCIES.txt) for full dependency list.
