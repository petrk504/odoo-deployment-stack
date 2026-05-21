# Odoo 18 Troubleshooting Guide

Complete troubleshooting reference for Odoo 18 on Ubuntu 24.04 with Caddy reverse proxy.

---

## 📋 Git & DevOps Issues

### Git SSH Authentication with Multiple GitHub Accounts

**Problem:**
- Git asks for HTTPS credentials (username/password) even though SSH keys exist
- Have two different GitHub accounts (e.g., `petrk504` and `petrk504`)
- Repository remote is configured for HTTPS instead of SSH
- SSH works for one account but not the other

**Root Cause:**
1. Repository remote URL uses HTTPS (`https://github.com/...`) instead of SSH (`git@github.com:...`)
2. Multiple GitHub accounts require different SSH keys
3. SSH config doesn't distinguish between accounts

**Solution:**

#### Step 1: Identify Your SSH Keys

```bash
ls -la ~/.ssh/

# You should see pairs like:
# id_fedora_pc / id_fedora_pc.pub      (for petrk504 account)
# id_fedora_gmail / id_fedora_gmail.pub (for petrk504 account)
```

#### Step 2: Configure SSH for Multiple Accounts

```bash
nano ~/.ssh/config
```

**Add this configuration:**

```
# Personal GitHub account (petrk504) - DEFAULT
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_fedora_pc
    IdentitiesOnly yes

# Work/Other GitHub account (petrk504)
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_fedora_gmail
    IdentitiesOnly yes
```

**Important:** You can only have ONE `Host github.com` entry. If you need both accounts to use custom hosts:

```
# Personal GitHub account
Host github-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_fedora_pc
    IdentitiesOnly yes

# Work GitHub account
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_fedora_gmail
    IdentitiesOnly yes
```

#### Step 3: Add SSH Keys to GitHub

For each account:

```bash
# Display public key
cat ~/.ssh/id_fedora_pc.pub

# Copy the ENTIRE output (from ssh-rsa to end)
```

Then:
1. Log into the correct GitHub account (e.g., petrk504)
2. Go to: https://github.com/settings/keys
3. Click "New SSH key"
4. Title: `Fedora PC` (or descriptive name)
5. Paste the public key
6. Click "Add SSH key"

Repeat for other account with the other key.

#### Step 4: Test SSH Connection

```bash
# Test default account
ssh -T git@github.com
# Should say: "Hi petrk504! You've successfully authenticated..."

# Test work account (if using custom host)
ssh -T git@github-work
# Should say: "Hi petrk504! You've successfully authenticated..."
```

#### Step 5: Update Repository Remote URL

```bash
cd ~/projects/odoo-deployment-stack

# Check current remote
git remote -v

# If it shows HTTPS (https://github.com/...)
# Change to SSH:
git remote set-url origin git@github.com:petrk504/odoo-deployment-stack.git

# Or if using custom host:
git remote set-url origin git@github-personal:petrk504/odoo-deployment-stack.git

# Verify
git remote -v

# Test
git pull origin main
```

**Should now work without asking for username/password!**

---

### Empty Folders on GitHub (Nested Git Repositories)

**Problem:**
- Folders like `account-financial-tools` and `reporting-engine` appear as greyed-out, empty folders on GitHub
- Folders cannot be clicked or opened
- Files exist locally but don't appear on GitHub

**Root Cause:**
**Nested Git Repositories.** The folders were cloned from OCA and contain their own `.git` directories. The parent Git repository ignores their contents to prevent conflicts, creating "broken links" instead of tracking files.

**Solution: Convert to Git Submodules**

Submodules are the proper way to include external repositories (like OCA modules) in your project.

#### What is a Git Submodule?

**Without Submodules:** You copy OCA code into your repo. If OCA updates, your copy is outdated. You must manually copy-paste updates.

**With Submodules:** You store a *reference* to the OCA repository at a specific commit, not the files themselves.

**Benefits:**
- ✅ Clean: Your repo stays small
- ✅ Easy Updates: `git submodule update --remote` to get latest
- ✅ Version Control: Lock to specific commits, won't break on OCA updates
- ✅ Proper: Industry standard for external dependencies

#### Convert Existing Folders to Submodules

```bash
# 1. Remove the "broken" nested repos
git rm --cached account-financial-tools reporting-engine
rm -rf account-financial-tools reporting-engine

# 2. Add them as proper submodules (pointing to 18.0 branch)
git submodule add -b 18.0 https://github.com/OCA/account-financial-tools.git account-financial-tools
git submodule add -b 18.0 https://github.com/OCA/reporting-engine.git reporting-engine

# 3. Commit the changes
git add .
git commit -m "fix: convert nested repos to proper submodules"
git push origin main
```

#### Clone Repository with Submodules

When cloning on a new machine:

```bash
# Clone with submodules
git clone --recurse-submodules git@github.com:petrk504/odoo-deployment-stack.git

# Or if already cloned without submodules:
git submodule init
git submodule update
```

#### Update Submodules

```bash
# Update all submodules to latest from their tracked branches
git submodule update --remote

# Commit the new references
git add .
git commit -m "Update OCA modules to latest"
git push origin main
```

#### Add New OCA Module

**Don't just clone!** Use submodule:

```bash
# Correct way to add new OCA module
git submodule add -b 18.0 https://github.com/OCA/repository-name.git folder-name

# Commit
git add .
git commit -m "Add new OCA module: folder-name"
git push origin main
```

---

### Git Workflow Best Practices

**Golden Rule:** Never edit files on the DigitalOcean server directly.

**Proper Workflow:**

```
Local PC → GitHub → DigitalOcean Server
   ↓          ↓           ↓
  Edit      Push        Pull
```

1. **Edit on Local PC/Mac**
   ```bash
   cd ~/projects/odoo-deployment-stack
   # Make changes
   git add .
   git commit -m "Description of changes"
   git push origin main
   ```

2. **Deploy to Server**
   ```bash
   # SSH into server
   ssh odoo-user@your-server-ip
   
   # Pull changes
   sudo -u odoo18 git -C /opt/odoo18/odoo18-custom-addons pull origin main
   
   # Restart service
   sudo systemctl restart odoo18
   ```

---

## 🚨 Critical Issues

### 1. Microsoft 365 Calendar OAuth Authentication Fails

**Symptoms:**
- Microsoft OAuth redirect fails during calendar sync setup
- Error: "Redirect URI mismatch"
- OAuth flow sends HTTP redirect URI instead of HTTPS
- Works locally but fails on production

**Root Cause:**
Reverse proxy (Nginx) not properly forwarding `X-Forwarded-Proto` header, causing Odoo to generate HTTP instead of HTTPS redirect URIs.

**Solution: Switch from Nginx to Caddy**

Caddy automatically handles all proxy headers correctly, including `X-Forwarded-Proto`.

**Step 1: Install Caddy**
```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

**Step 2: Stop Nginx**
```bash
sudo systemctl stop nginx
sudo systemctl disable nginx
```

**Step 3: Configure Caddy**
```bash
sudo nano /etc/caddy/Caddyfile
```

**Paste:**
```
test.example.com {
    reverse_proxy 127.0.0.1:8069
}

prod.example.com {
    reverse_proxy 127.0.0.1:8070
}
```

**Step 4: Start Caddy**
```bash
sudo systemctl enable caddy
sudo systemctl start caddy
```

**Step 5: Clean Database Settings**
```bash
# Clear frozen base URL
sudo -u odoo18 psql -d YOUR_DATABASE -c "DELETE FROM ir_config_parameter WHERE key = 'web.base.url.freeze';"

# Set HTTPS base URL
sudo -u odoo18 psql -d YOUR_DATABASE -c "UPDATE ir_config_parameter SET value = 'https://test.example.com' WHERE key = 'web.base.url';"

# Clear Microsoft tokens
sudo -u odoo18 psql -d YOUR_DATABASE -c "DELETE FROM ir_config_parameter WHERE key LIKE 'microsoft_calendar_token%' OR key LIKE 'microsoft_calendar_rtoken%';"

# Restart Odoo
sudo systemctl restart odoo18
```

**Step 6: Verify**
- Wait 30 seconds for SSL certificate
- Visit `https://test.example.com`
- Try Microsoft Calendar sync again

**Alternative: Fix Nginx (Not Recommended)**

If you must use Nginx, add these headers:

```nginx
location / {
    proxy_pass http://127.0.0.1:8069;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;  # CRITICAL
    proxy_set_header X-Forwarded-Host $host;
    proxy_redirect off;
}
```

---

## 🔧 Service & Startup Issues

### 2. Service Won't Start (`status=2` or `status=203`)

**Symptoms:**
- `sudo systemctl status odoo18` shows failed/inactive
- Exit code 2 or 203
- Service stops immediately after starting

**Diagnosis:**
```bash
# Check service status
sudo systemctl status odoo18

# View full logs
sudo journalctl -u odoo18 -n 100 --no-pager

# Check Odoo logs
sudo tail -100 /var/log/odoo18/odoo18.log
```

**Common Causes:**

**A. Wrong Python/venv path**
```bash
# Verify paths in service file
sudo nano /etc/systemd/system/odoo18.service

# Should be:
ExecStart=/opt/odoo18/odoo18-venv/bin/python /opt/odoo18/odoo/odoo-bin -c /etc/odoo18.conf

# Test manually
sudo -u odoo18 /opt/odoo18/odoo18-venv/bin/python /opt/odoo18/odoo/odoo-bin -c /etc/odoo18.conf
```

**B. Missing Python dependencies**
```bash
sudo su - odoo18
source /opt/odoo18/odoo18-venv/bin/activate
pip install -r /opt/odoo18/odoo/requirements.txt
pip install -r /opt/odoo18/odoo18-custom-addons/REPO_NAME/requirements.txt
deactivate
logout
sudo systemctl restart odoo18
```

**C. Permissions errors**
```bash
# Fix ownership
sudo chown -R odoo18:odoo18 /opt/odoo18/
sudo chown -R odoo18:odoo18 /var/log/odoo18/

# Fix log directory
sudo mkdir -p /var/log/odoo18/
sudo chown -R odoo18:odoo18 /var/log/odoo18/
```

**D. Config file errors**
```bash
# Validate config syntax
sudo nano /etc/odoo18.conf

# Check for:
# - Correct paths
# - No trailing spaces
# - Valid INI syntax
# - proxy_mode = True (if using reverse proxy)
```

**E. Port already in use**
```bash
# Check if port 8069 is already bound
sudo netstat -tulpn | grep 8069

# If another process is using it, kill it or change port in config
```

### 3. "Internal Server Error" / 500 Errors

**Symptoms:**
- Browser shows "Internal Server Error"
- Odoo interface returns HTTP 500

**Diagnosis:**
```bash
# Always check logs first
sudo tail -f /var/log/odoo18/odoo18.log

# Look for Python tracebacks
sudo grep -A 20 "Traceback" /var/log/odoo18/odoo18.log
```

**Common Causes:**

**A. Missing Python module dependency**
```
ImportError: No module named 'xlrd'
```

**Solution:**
```bash
sudo su - odoo18
source /opt/odoo18/odoo18-venv/bin/activate
pip install xlrd  # or whatever module is missing
deactivate
logout
sudo systemctl restart odoo18
```

**B. Database connection error**
```
FATAL: Ident authentication failed for user "odoo18"
```

**Solution:**
```bash
# Verify PostgreSQL user exists
sudo -u postgres psql -c "\du" | grep odoo18

# Create if missing
sudo -u postgres createuser -s odoo18

# Check pg_hba.conf authentication
sudo nano /etc/postgresql/*/main/pg_hba.conf
# Should have: local all all peer
```

**C. Invalid addon code**
```
SyntaxError: invalid syntax
```

**Solution:**
- Check the specific file mentioned in traceback
- Fix Python syntax error
- Restart service

---

## 📦 Module & Addon Issues

### 4. New Modules Don't Appear in Apps List

**Symptoms:**
- Custom modules not visible after deployment
- "Update Apps List" doesn't find new modules
- Database query shows 0 results:
  ```sql
  SELECT name FROM ir_module_module WHERE name = 'your_module';
  ```

**Root Cause:**
1. `addons_path` not configured correctly
2. Missing Python dependencies
3. Module folder missing `__manifest__.py`

**Solution:**

**Step 1: Verify addons_path**
```bash
sudo nano /etc/odoo18.conf
```

**WRONG:**
```ini
addons_path = /opt/odoo18/odoo/addons,/opt/odoo18/odoo18-custom-addons
```

**CORRECT:**
```ini
addons_path = /opt/odoo18/odoo/addons,
              /opt/odoo18/odoo18-custom-addons/account-financial-tools,
              /opt/odoo18/odoo18-custom-addons/reporting-engine
```

Each repository must be listed individually. Odoo does NOT scan subfolders.

**Step 2: Check module structure**
```bash
# Must have __manifest__.py or __openerp__.py
ls /opt/odoo18/odoo18-custom-addons/your-repo/module_name/

# Should show:
__manifest__.py
__init__.py
models/
views/
```

**Step 3: Install dependencies**
```bash
sudo su - odoo18
source /opt/odoo18/odoo18-venv/bin/activate

# For each repository
pip install -r /opt/odoo18/odoo18-custom-addons/REPO_NAME/requirements.txt

deactivate
logout
```

**Step 4: Restart and update**
```bash
sudo systemctl restart odoo18

# In Odoo UI:
# 1. Enable Developer Mode (Settings → Activate Developer Mode)
# 2. Go to Apps
# 3. Click "Update Apps List"
# 4. Remove "Apps" filter from search bar
# 5. Search for your module
```

**Step 5: Verify in database**
```bash
sudo -u odoo18 psql -d YOUR_DATABASE

SELECT name, state FROM ir_module_module WHERE name = 'your_module_name';
# Should return 1 row with state 'uninstalled'
```

### 5. Module Installation Fails

**Symptoms:**
- Module shows in list but won't install
- Errors during installation
- Database constraint violations

**Diagnosis:**
```bash
# Check logs during installation
sudo tail -f /var/log/odoo18/odoo18.log
```

**Common Issues:**

**A. Missing Python dependencies**
```
ModuleNotFoundError: No module named 'package_name'
```

**Solution:**
```bash
sudo su - odoo18
source /opt/odoo18/odoo18-venv/bin/activate
pip install package_name
deactivate
logout
sudo systemctl restart odoo18
```

**B. Conflicting modules**
```
IntegrityError: duplicate key value violates unique constraint
```

**Solution:**
- Check for duplicate modules
- Remove conflicting module
- Update module if upgrading

**C. Missing dependent modules**
```
The following modules are required: ['base_import', 'account']
```

**Solution:**
- Install dependency modules first
- Check `depends` in `__manifest__.py`

---

## 🔐 Permission Issues

### 6. "Permission Denied" Errors

**Symptoms:**
- `[Errno 13] Permission denied`
- Service fails with `status=203`
- Can't write to log file

**Solution:**

**Fix all ownership:**
```bash
# Odoo directories
sudo chown -R odoo18:odoo18 /opt/odoo18/

# Log directory
sudo chown -R odoo18:odoo18 /var/log/odoo18/

# Verify
ls -la /opt/odoo18/
ls -la /var/log/odoo18/
```

**Check service user:**
```bash
sudo nano /etc/systemd/system/odoo18.service

# Must have:
User=odoo18
Group=odoo18
```

**Fix git permissions (for deployments):**
```bash
# If you get permission errors during git pull
sudo chown -R odoo18:odoo18 /opt/odoo18/odoo18-custom-addons/.git
```

---

## 🌐 Network & Connection Issues

### 7. "Connection Refused" or "Site Can't Be Reached"

**Symptoms:**
- Can't access Odoo via domain or IP
- Browser shows "Connection refused"
- `ERR_CONNECTION_REFUSED`

**Diagnosis:**
```bash
# Check if Odoo is running
sudo systemctl status odoo18

# Check if listening on port
sudo netstat -tulpn | grep 8069

# Check Caddy is running
sudo systemctl status caddy

# Check Caddy is listening
sudo netstat -tulpn | grep -E '80|443'
```

**Solutions:**

**A. Odoo service not running**
```bash
sudo systemctl start odoo18
sudo systemctl status odoo18
```

**B. Firewall blocking**
```bash
# Check firewall status
sudo ufw status

# Allow required ports
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Do NOT allow 8069 (should be behind proxy)
sudo ufw delete allow 8069/tcp
sudo ufw reload
```

**C. Caddy not configured**
```bash
# Check Caddyfile
sudo nano /etc/caddy/Caddyfile

# Should have your domain
sudo systemctl restart caddy
```

**D. DNS not pointing to server**
```bash
# Check DNS resolution
dig test.example.com

# Should return your server IP
```

### 8. SSL Certificate Issues

**Symptoms:**
- "Your connection is not private"
- SSL certificate errors
- Certificate expired

**Diagnosis:**
```bash
# Check Caddy logs
sudo journalctl -u caddy -n 100

# Test certificate
curl -vI https://test.example.com 2>&1 | grep -i 'certificate\|SSL'
```

**Solutions:**

**A. Certificate not obtained**
```bash
# Caddy should auto-obtain, but you can force restart
sudo systemctl restart caddy

# Wait 30-60 seconds
# Check logs
sudo journalctl -u caddy -f
```

**B. Port 80 blocked**

Caddy needs port 80 for Let's Encrypt challenge:
```bash
sudo ufw allow 80/tcp
sudo ufw status
```

**C. Domain not pointing to server**

Verify DNS before restarting Caddy:
```bash
dig +short test.example.com
# Should show your server IP
```

---

## 🗄️ Database Issues

### 9. "Database Creation Failed"

**Symptoms:**
- Can't create database through Odoo UI
- `FATAL: database creation error`

**Solution:**

**A. PostgreSQL user missing**
```bash
sudo -u postgres createuser -s odoo18
```

**B. No superuser privileges**
```bash
sudo -u postgres psql
ALTER USER odoo18 CREATEDB;
\q
```

**C. Disk space full**
```bash
df -h
# Check if /var/lib/postgresql is full
```

### 10. Database Connection Errors

**Symptoms:**
- `could not connect to server`
- `FATAL: Ident authentication failed`

**Solution:**

**A. PostgreSQL not running**
```bash
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

**B. Wrong authentication method**
```bash
sudo nano /etc/postgresql/*/main/pg_hba.conf

# For local connections, use:
local   all   all   peer

# Restart PostgreSQL
sudo systemctl restart postgresql
```

---

## 🔄 Update & Deployment Issues

### 11. Git Pull Fails

**Symptoms:**
- Permission denied during `git pull`
- `fatal: unable to access`

**Solution:**

**A. Ownership issues**
```bash
sudo chown -R odoo18:odoo18 /opt/odoo18/odoo18-custom-addons/
```

**B. Must run as odoo user**
```bash
# WRONG (as root or odoo-user user):
git -C /opt/odoo18/odoo18-custom-addons pull

# CORRECT:
sudo -u odoo18 git -C /opt/odoo18/odoo18-custom-addons pull origin main
```

**C. SSH key not set up**

If using git@github.com URLs:
```bash
# Generate SSH key as odoo18 user
sudo -u odoo18 ssh-keygen -t ed25519 -C "odoo@server"

# Copy public key
sudo -u odoo18 cat ~/.ssh/id_ed25519.pub

# Add to GitHub: Settings → SSH Keys
```

---

## 📊 Performance Issues

### 12. Slow Response Times

**Symptoms:**
- Pages take >5 seconds to load
- Database queries slow

**Diagnosis:**
```bash
# Check system resources
htop

# Check disk I/O
iostat -x 1

# Check PostgreSQL connections
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;"
```

**Solutions:**

**A. Increase worker processes**
```bash
sudo nano /etc/odoo18.conf

# Add:
workers = 4  # Or: (CPU cores * 2) + 1
max_cron_threads = 2
```

**B. Enable database pooling**
```bash
sudo nano /etc/odoo18.conf

# Add:
db_maxconn = 64
```

**C. PostgreSQL tuning**
```bash
sudo nano /etc/postgresql/*/main/postgresql.conf

# Increase:
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 16MB
```

---

## 🧹 Maintenance Tasks

### Clean Old Sessions

```bash
sudo -u odoo18 psql -d YOUR_DATABASE -c "DELETE FROM ir_session WHERE write_date < NOW() - INTERVAL '7 days';"
```

### Clean Logs

```bash
# Truncate log file
sudo truncate -s 0 /var/log/odoo18/odoo18.log

# Or rotate logs
sudo logrotate -f /etc/logrotate.d/odoo18
```

### Vacuum Database

```bash
sudo -u postgres psql -d YOUR_DATABASE -c "VACUUM ANALYZE;"
```

---

## 🔍 Debugging Tools

### Enable Debug Mode in Odoo

**Method 1: URL parameter**
```
https://test.example.com/web?debug=1
```

**Method 2: Settings**
1. Settings → Activate Developer Mode

### Check Loaded Modules

```bash
sudo -u odoo18 psql -d YOUR_DATABASE

SELECT name, state FROM ir_module_module WHERE state = 'installed' ORDER BY name;
```

### View Active Sessions

```bash
sudo -u odoo18 psql -d YOUR_DATABASE

SELECT * FROM ir_session WHERE create_date > NOW() - INTERVAL '1 hour';
```

### Monitor Live Queries

```bash
sudo -u postgres psql

SELECT pid, now() - query_start AS duration, query 
FROM pg_stat_activity 
WHERE state = 'active' 
ORDER BY duration DESC;
```

---

## 📞 Emergency Procedures

### Complete Service Restart

```bash
sudo systemctl restart postgresql
sudo systemctl restart odoo18
sudo systemctl restart caddy
```

### Factory Reset Instance (DANGER)

```bash
# Stop service
sudo systemctl stop odoo18

# Drop all databases
sudo -u postgres psql -c "DROP DATABASE database_name;"

# Clean logs
sudo truncate -s 0 /var/log/odoo18/odoo18.log

# Start fresh
sudo systemctl start odoo18
```

### Restore from Backup

```bash
# Stop service
sudo systemctl stop odoo18

# Drop current database
sudo -u postgres psql -c "DROP DATABASE production_db;"

# Restore from backup
sudo -u postgres psql -c "CREATE DATABASE production_db;"
sudo -u postgres psql production_db < ~/backup_20250215.sql

# Start service
sudo systemctl start odoo18
```

---

## 📚 Related Documentation

- **[README.md](./README.md)** - Main maintenance guide
- **[install-odoo-18.md](./install-odoo-18.md)** - Installation guide
- **[PRODUCTION-SETUP.md](./PRODUCTION-SETUP.md)** - Production deployment

---

**Last Updated:** February 2026  
**Maintained by:** Client Company
