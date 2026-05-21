# SSH Key Setup for Git - Troubleshooting Guide

**How to set up SSH keys for GitHub Git operations without password prompts.**

*Last Updated: March 17, 2026*

---

## The Problem

When using `git push`, `git pull`, or `git fetch`, you get prompted for username/password/token every time:
```bash
Username for 'https://github.com': petrk504
Password for 'https://petrk504@github.com':
fatal: Authentication failed for 'https://github.com/...'
```

**Why:** Git is configured to use HTTPS (requires token) instead of SSH (uses keys).

---

## The Solution: SSH Keys + ssh-agent

SSH keys allow you to authenticate without entering passwords/tokens every time.

### What You Need

1. **SSH Key Pair** (private + public key)
2. **ssh-agent** running (loads keys into memory)
3. **Public key added to GitHub**

---

## Step-by-Step Setup

### Step 1: Check if SSH Keys Already Exist

```bash
ls -la ~/.ssh/
```

**Look for:**
- `id_ed25519` and `id_ed25519.pub` ✅ (modern, recommended)
- OR `id_rsa` and `id_rsa.pub` ✅ (older format)
- OR any other key pair

**If keys exist:** Skip to Step 3

**If no keys exist:** Go to Step 2

---

### Step 2: Generate New SSH Key

```bash
# Generate ed25519 key (recommended, modern, secure)
ssh-keygen -t ed25519 -C "odoo-user@ubuntu-droplet"

# Or generate RSA key (older, more compatible)
ssh-keygen -t rsa -b 4096 -C "odoo-user@ubuntu-droplet"
```

**Prompts:**
```
Enter file in which to save the key (/home/odoo-user/.ssh/id_ed25519):
# Press Enter (use default location)

Enter passphrase (empty for no passphrase):
# Press Enter (no passphrase for convenience)

Enter same passphrase again:
# Press Enter
```

**Output:**
```
Your identification has been saved in /home/odoo-user/.ssh/id_ed25519
Your public key has been saved in /home/odoo-user/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:...
```

---

### Step 3: Copy Your Public Key

```bash
# Display your public key
cat ~/.ssh/id_ed25519.pub
# OR
cat ~/.ssh/id_rsa.pub
```

**Copy the ENTIRE output** - it looks like:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC... odoo-user@ubuntu-droplet
```

**Example:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC8r9g5L8vN9t8p7qY2xXw3kK8mZ5vK8cL9dY8mN5vK8cL9dY odoo-user@ubuntu-droplet
```

---

### Step 4: Add SSH Key to GitHub

#### Option A: Via GitHub Web (Recommended)

1. **Go to:** https://github.com/settings/keys
2. **Click:** "New SSH key"
3. **Title:** `Ubuntu Droplet` (or descriptive name)
4. **Key type:** "Authentication Key"
5. **Key:** Paste your public key (from Step 3)
6. **Click:** "Add SSH key"

#### Option B: Via GitHub CLI (If Installed)

```bash
# Install GitHub CLI
sudo apt install -y gh

# Login to GitHub
gh auth login

# Add SSH key
gh ssh-key add ~/.ssh/id_ed25519.pub --title "Ubuntu Droplet"
```

---

### Step 5: Start ssh-agent

```bash
# Check if ssh-agent is running
ps aux | grep ssh-agent

# If NOT running, start it:
eval "$(ssh-agent -s)"

# Output: Agent pid 123456
```

**⚠️ IMPORTANT:** ssh-agent must be running for git to use your SSH keys!

---

### Step 6: Add Your Key to ssh-agent

```bash
# Add your private key to ssh-agent
ssh-add ~/.ssh/id_ed25519
# OR
ssh-add ~/.ssh/id_rsa

# Output: Identity added: ... (odoo-user@ubuntu-droplet)
```

---

### Step 7: Test SSH Connection

```bash
# Test SSH connection to GitHub
ssh -T git@github.com
```

**Expected output:**
```
Hi petrk504! You've successfully authenticated, but GitHub does not provide shell access.
```

**If you see this:** ✅ SSH is working!

**Error messages:**
- `Permission denied (publickey)` → Key not in ssh-agent or not added to GitHub
- `Could not resolve hostname` → Network issue

---

### Step 8: Configure Git to Use SSH

```bash
# Go to your git repository
cd ~/path/to/your/repo

# Check current remote URL
git remote -v

# If shows HTTPS:
# origin  https://github.com/username/repo.git (fetch)
# origin  https://github.com/username/repo.git (push)

# Change to SSH:
git remote set-url origin git@github.com:username/repo.git

# Verify change
git remote -v

# Should show:
# origin  git@github.com:username/repo.git (fetch)
# origin  git@github.com:username/repo.git (push)
```

---

### Step 9: Test Git Operations

```bash
# Now these should work WITHOUT password prompts:
git fetch
git pull
git push
```

**No password/token prompts!** ✅

---

## Making ssh-agent Persistent

**Problem:** ssh-agent dies when you close your terminal.

**Solution:** Auto-start ssh-agent on login.

### Option A: Add to .bashrc (Recommended)

```bash
# Add to ~/.bashrc
echo 'eval "$(ssh-agent -s)"' >> ~/.bashrc
echo 'ssh-add ~/.ssh/id_ed25519 > /dev/null 2>&1' >> ~/.bashrc

# Reload .bashrc
source ~/.bashrc
```

**Now ssh-agent starts automatically** every time you open a terminal!

### Option B: Use Systemd Service (More Robust)

```bash
# Create systemd service
sudo nano ~/.config/systemd/user/ssh-agent.service
```

**Add:**
```ini
[Unit]
Description=SSH key agent

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket
ExecStart=/usr/bin/ssh-agent -D -a $SSH_AUTH_SOCK

[Install]
WantedBy=default.target
```

```bash
# Enable service
systemctl --user enable ssh-agent.service
systemctl --user start ssh-agent.service

# Add to ~/.bashrc
echo 'export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"' >> ~/.bashrc
```

---

## Troubleshooting

### Issue 1: ssh-agent Not Running

**Symptoms:**
```bash
ssh -T git@github.com
Permission denied (publickey)
```

**Diagnosis:**
```bash
ps aux | grep ssh-agent
# Shows only grep process, no ssh-agent
```

**Solution:**
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
ssh -T git@github.com
```

### Issue 2: Key Not Added to ssh-agent

**Symptoms:**
```bash
ssh -T git@github.com
Permission denied (publickey)
```

**Diagnosis:**
```bash
ssh-add -l
# The agent has no identities
```

**Solution:**
```bash
ssh-add ~/.ssh/id_ed25519
ssh -T git@github.com
```

### Issue 3: Wrong Key Added to GitHub

**Symptoms:**
```bash
ssh -T git@github.com
Permission denied (publickey)
```

**Diagnosis:**
```bash
# Show your public key
cat ~/.ssh/id_ed25519.pub

# Compare with what's in GitHub
# Go to: https://github.com/settings/keys
```

**Solution:**
```bash
# Copy public key again
cat ~/.ssh/id_ed25519.pub

# Delete old key from GitHub
# Add new key to GitHub
# Test again
ssh -T git@github.com
```

### Issue 4: Multiple Keys (Which One is Being Used?)

**Diagnosis:**
```bash
# Verbose SSH connection
ssh -vT git@github.com 2>&1 | grep -i "offering\|identity"

# Shows which key git is trying to use
```

**Solution:**
```bash
# Create/configure ~/.ssh/config
nano ~/.ssh/config
```

**Add:**
```
Host github.com
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

### Issue 5: Git Still Asking for Password

**Symptoms:**
```bash
git push
Username for 'https://github.com':
```

**Diagnosis:**
```bash
git remote -v
# Shows HTTPS URL instead of SSH
```

**Solution:**
```bash
git remote set-url origin git@github.com:username/repo.git
git remote -v
```

---

## Quick Reference Commands

### Check SSH Setup
```bash
# List keys
ls -la ~/.ssh/

# Show public key
cat ~/.ssh/id_ed25519.pub

# Check ssh-agent
ps aux | grep ssh-agent

# Check loaded keys
ssh-add -l

# Test connection
ssh -T git@github.com

# Check git remote
git remote -v
```

### Fix Common Issues
```bash
# Start ssh-agent
eval "$(ssh-agent -s)"

# Add key to agent
ssh-add ~/.ssh/id_ed25519

# Test SSH
ssh -T git@github.com

# Change remote to SSH
git remote set-url origin git@github.com:username/repo.git

# Test git
git fetch
```

---

## Security Best Practices

### ✅ DO
1. Use SSH keys instead of HTTPS
2. Use ed25519 keys (modern, secure)
3. Add passphrase to key (optional, more secure)
4. Use ssh-agent to cache passphrase
5. Add only public key to GitHub (keep private key secret!)

### ❌ DON'T
1. Never share your private key (`id_ed25519`)
2. Never add private key to GitHub
3. Don't commit keys to git
4. Don't use same key everywhere (create per device)

---

## Summary

**Complete Setup:**
1. Generate SSH key: `ssh-keygen -t ed25519`
2. Copy public key: `cat ~/.ssh/id_ed25519.pub`
3. Add to GitHub: https://github.com/settings/keys
4. Start ssh-agent: `eval "$(ssh-agent -s)"`
5. Add key: `ssh-add ~/.ssh/id_ed25519`
6. Test: `ssh -T git@github.com`
7. Configure git: `git remote set-url origin git@github.com:...`
8. Make persistent: Add to ~/.bashrc

**Result:** No more password prompts! ✅

---

## Real-World Example: This Setup

**Environment:** Ubuntu 24.04 Droplet
**User:** odoo-user
**Key:** id_ubuntu_vina_droplet
**Issue:** Permission denied until ssh-agent started

**What Worked:**
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ubuntu_vina_droplet
ssh -T git@github.com
# Output: Hi petrk504! You've successfully authenticated...
```

**Lesson:** Always start ssh-agent and add keys before using git!
