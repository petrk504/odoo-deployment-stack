# Git Workflow Guide - Odoo Deployment Stack

**How to properly track custom modules and manage git permissions.**

*Last Updated: March 17, 2026*

---

## The Problem

**Current Issues:**
1. You can only commit as `odoo18` user in `/opt/odoo18/odoo18-custom-addons`
2. Vendored modules (Cybrosys) are tracked in git (bloating repo)
3. Git repo is in bare-metal location, not your home directory

**Why This Happens:**
- Git repo was cloned as `odoo18` user
- File ownership doesn't match your `odoo-user` user
- Git remotes may have authentication configured for odoo18 user

---

## The Solution: Reorganize Repository

### Step 1: Clone Repo as odoo-user User (Your Home Directory)

```bash
# 1. Navigate to your home directory
cd ~

# 2. Clone the repo as odoo-user user
git clone https://github.com/petrk504/odoo-deployment-stack.git

# Or if it already exists, fix ownership:
sudo chown -R odoo-user:odoo-user ~/odoo-deployment-stack

# 3. Now you can commit as odoo-user user!
cd ~/odoo-deployment-stack
git status
```

### Step 2: Remove Vendored Modules from Git Tracking

```bash
cd ~/odoo-deployment-stack

# 1. Remove Cybrosys modules from git tracking
git rm -r base_accounting_kit/
git rm -r base_account_budget/

# 2. Move them to proper location
mkdir -p ~/addons/cybrosys
git mv base_accounting_kit/ ~/addons/cybrosys/  # This won't work, so use:
mv base_accounting_kit/ ~/addons/cybrosys/
mv base_account_budget/ ~/addons/cybrosys/

# 3. Add to .gitignore
echo "addons/" >> .gitignore

# 4. Commit the changes
git add .gitignore EXTERNAL-DEPENDENCIES.txt
git commit -m "refactor: Move vendored modules out of git

- Moved Cybrosys modules to ~/addons/cybrosys/
- Added EXTERNAL-DEPENDENCIES.txt to document external modules
- Updated .gitignore to exclude addons directory

These modules are now managed separately as documented in EXTERNAL-DEPENDENCIES.txt"

git push
```

### Step 3: Set Up Custom Addons Directory

```bash
cd ~/odoo-deployment-stack

# 1. Create custom addons directory (tracked in git)
mkdir -p addons/custom

# 2. Add placeholder README
cat > addons/custom/README.md << 'EOF'
# Custom Odoo Modules - MyClient Hotel

This directory contains custom-developed Odoo modules for MyClient Hotel.

## Modules

### myclient_whatsapp (Future)
- Custom WhatsApp integration for hotel guests
- Will be developed based on requirements

### myclient_hotel (Future)
- Hotel-specific customizations
- Property management features

## Development

When creating new modules:
1. Create module directory here
2. Follow Odoo module structure
3. Commit to git
4. Symlink to ~/docker/test/addons/custom for testing
EOF

# 3. Commit to git
git add addons/custom/README.md
git commit -m "feat: Add custom addons directory structure"
git push
```

### Step 4: Create Symlink for Docker

```bash
# 1. Navigate to docker test directory
cd ~/docker/test

# 2. Create symlink from ~/addons to docker directory
# This allows docker-compose.yml to use ./addons while pointing to ~/addons
ln -s ~/addons addons

# 3. Verify
ls -la addons/
# Should show: addons -> ~/addons

# 4. Test docker-compose
sudo docker-compose config
```

---

## Proper Git Workflow Going Forward

### For odoo-user User (Recommended)

```bash
# 1. Work in your home directory
cd ~/odoo-deployment-stack

# 2. Create custom module
mkdir -p addons/custom/my_module

# 3. Develop and commit
git add addons/custom/my_module/
git commit -m "feat: Add my custom module"
git push
```

### For odoo18 User (Legacy - Not Recommended)

```bash
# Only use this for bare-metal deployments
cd /opt/odoo18/odoo18-custom-addons

# Make changes
git add .
git commit -m "update"
```

**Why this is bad:**
- Mixing deployment (bare-metal) with source code (git)
- Permission issues
- Hard to work with as odoo-user user

---

## Fixing Git Permission Issues

### Diagnosis

```bash
# Check git remote configuration
cd ~/odoo-deployment-stack  # or /opt/odoo18/odoo18-custom-addons
git remote -v

# Check file ownership
ls -la .git/config
ls -la .git/

# Check current user
whoami
```

### Solution A: Fix Ownership (Quickest)

```bash
# Change ownership of entire repo to odoo-user
sudo chown -R odoo-user:odoo-user ~/odoo-deployment-stack

# Verify
ls -la ~/odoo-deployment-stack/.git/config
```

### Solution B: Set Up SSH Keys (Recommended - No Passwords)

**See:** `SSH-SETUP-GUIDE.md` for complete instructions.

**Quick start:**
```bash
# 1. Generate SSH key
ssh-keygen -t ed25519 -C "odoo-user@ubuntu-droplet"

# 2. Copy public key
cat ~/.ssh/id_ed25519.pub

# 3. Add to GitHub: https://github.com/settings/keys

# 4. Start ssh-agent (REQUIRED!)
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 5. Test
ssh -T git@github.com

# 6. Change remote to SSH
git remote set-url origin git@github.com:petrk504/odoo-deployment-stack.git
```

### Solution C: Reconfigure Git Remote (Use HTTPS)

```bash
cd ~/odoo-deployment-stack

# Check current remote
git remote -v

# If using SSH, switch to HTTPS (easier)
git remote set-url origin https://github.com/petrk504/odoo-deployment-stack.git

# Or configure SSH key for odoo-user user
# See: https://docs.github.com/en/authentication/connecting-to-github-with-ssh
```

### Solution C: Use Git Credential Helper

```bash
# Configure git to remember credentials
git config --global credential.helper store

# Next time you push, enter username and password
# Git will remember them for future pushes
```

---

## Recommended Directory Structure (Final)

```
~/odoo-deployment-stack/              # Git repo (owned by odoo-user)
├── .git/
├── CLAUDE.md
├── README.md
├── DOCKER-DEPLOYMENT-GUIDE.md
├── EXTERNAL-DEPENDENCIES.txt
├── GIT-WORKFLOW-GUIDE.md
├── scripts/                       # Automation scripts
├── addons/                        # ← TRACKED IN GIT
│   └── custom/                    # ← Only custom modules here
│       └── README.md
│       └── (future custom modules)
└── .gitignore
    ├── addons/oca/
    ├── addons/cybrosys/
    └── *.tar.gz

~/addons/                          # ← NOT in git (external deps)
├── oca/
│   ├── social/
│   ├── account-financial-tools/
│   └── reporting-engine/
├── cybrosys/
│   ├── base_accounting_kit/
│   └── base_account_budget/
└── custom -> ../odoo-deployment-stack/addons/custom  # Symlink to git repo

~/docker/test/
├── docker-compose.yml
├── .env
└── addons -> ~/addons/  # Symlink for docker-compose

~/docker/prod/
├── docker-compose.yml
├── .env
└── addons -> ~/addons/  # Symlink for docker-compose
```

---

## Working with Custom Modules

### Creating a New Custom Module

```bash
# 1. Create module in git repo
cd ~/odoo-deployment-stack/addons/custom
mkdir myclient_whatsapp
cd myclient_whatsapp

# 2. Create module structure
cat > __manifest__.py << 'EOF'
{
    'name': 'MyClient WhatsApp Integration',
    'version': '1.0.0',
    'category': 'Social',
    'summary': 'Custom WhatsApp integration for MyClient Hotel',
    'author': 'Petr',
    'depends': ['base', 'mail'],
    'data': [],
    'installable': True,
    'application': True,
}
EOF

# 3. Commit to git
cd ~/odoo-deployment-stack
git add addons/custom/myclient_whatsapp/
git commit -m "feat: Add MyClient WhatsApp module skeleton"
git push

# 4. Deploy to test (symlink already exists)
# Just restart Odoo
cd ~/docker/test
sudo docker-compose restart
```

### Updating Custom Module

```bash
# 1. Edit files
cd ~/odoo-deployment-stack/addons/custom/myclient_whatsapp
vim __manifest__.py

# 2. Commit changes
cd ~/odoo-deployment-stack
git add addons/custom/myclient_whatsapp/
git commit -m "feat: Add feature X to WhatsApp module"
git push

# 3. Pull on droplet and restart
cd ~/odoo-deployment-stack
git pull

cd ~/docker/test
sudo docker-compose restart
```

---

## Deployment Workflow

### From Local (Fedora) to Droplet

```bash
# On Fedora laptop
cd ~/projects/odoo-deployment-stack
# Make changes
git add .
git commit -m "update"
git push

# On droplet
cd ~/odoo-deployment-stack
git pull

# Restart Odoo
cd ~/docker/test
sudo docker-compose restart
```

---

## Troubleshooting Git Issues

### "Permission denied" when committing

```bash
# Fix ownership
sudo chown -R $USER:$USER ~/odoo-deployment-stack

# Try again
git status
```

### "Failed to push" - Authentication error

```bash
# Switch to HTTPS (easier)
git remote set-url origin https://github.com/petrk504/odoo-deployment-stack.git

# Push again
git push
```

### "Changes not staged for commit" but you didn't change anything

```bash
# Line ending issues (Windows/Linux)
git config --global core.autocrlf input

# Reset to HEAD
git reset --hard HEAD

# Pull clean
git pull
```

---

## Best Practices

### DO ✅

1. **Track only custom modules** in git
2. **Document external dependencies** in EXTERNAL-DEPENDENCIES.txt
3. **Use symlinks** for docker-compose to access addons
4. **Work as odoo-user user** in ~/odoo-deployment-stack
5. **Commit often** with meaningful messages
6. **Use .gitignore** for build artifacts, backups, dependencies

### DON'T ❌

1. **Don't track OCA modules** in git
2. **Don't track Cybrosys modules** in git
3. **Don't work in /opt/odoo18/** as odoo-user (permission issues)
4. **Don't commit .env files** (contains passwords)
5. **Don't commit backup files** (*.sql, *.tar.gz)
6. **Don't use bare-metal location** for git operations

---

## Summary

**Repository Location:** `~/odoo-deployment-stack/` (your home directory)
**Custom Modules:** `~/odoo-deployment-stack/addons/custom/` (tracked in git)
**External Modules:** `~/addons/` (NOT tracked, documented in EXTERNAL-DEPENDENCIES.txt)
**Docker Access:** Via symlink `~/docker/test/addons -> ~/addons`

**Git User:** `odoo-user` (not odoo18)
**Git Remote:** https://github.com/petrk504/odoo-deployment-stack.git

This setup gives you:
- ✅ Clean git history (only your code)
- ✅ No permission issues
- ✅ Clear documentation of dependencies
- ✅ Easy deployment workflow
- ✅ Separation of concerns (custom vs external)
