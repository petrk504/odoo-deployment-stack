Here is the updated, comprehensive guide. It now includes **both** methods so you can choose the best one for your situation (saving disk space vs. easier future updates).

### 📝 Save this file as: `WORKFLOW_ADD_ACCOUNTING.md`

---

# Workflow: Adding Base Accounting Kit (Odoo 18)

**Flow:** Local Mac (Prepare) → GitHub (Store) → DigitalOcean (Deploy)

---

## 📍 PART 1: Work on Your Mac First

We prepare the module on your machine first.

### Step 1: Clone Your Repository

Start fresh or navigate to your project folder.
**💻 ON YOUR MAC:**

```bash
# Navigate to your projects folder
cd ~/Projects

# Clone your private repository (if not already there)
git clone git@github.com:petrk504/odoo-deployment-stack.git

# Enter the directory
cd odoo-deployment-stack

```

### Step 2: Add The Modules (Choose Option A or B)

**Choose ONE option below.**

#### 🅰️ Option A: Git Submodule (Professional)

* **Pros:** Easy to update later (`git submodule update --remote`).
* **Cons:** Downloads the **entire** Cybrosys repository (hundreds of apps), using significant disk space on Mac and Server.

```bash
# 1. Add the repo as a submodule named 'cybro-addons'
git submodule add -b 18.0 https://github.com/CybroOdoo/CybroAddons.git cybro-addons

# 2. Initialize and download the files (This may take time)
git submodule update --init --recursive

```

#### 🅱️ Option B: Manual Copy / Vendoring (Space Saving)

* **Pros:** Only adds the specific files you need. Very light on disk space.
* **Cons:** Updating requires manually downloading and replacing files in the future.

1. Download the **ZIP** of the repository from [GitHub CybroAddons 18.0](https://github.com/CybroOdoo/CybroAddons/tree/18.0).
2. Unzip it on your Mac.
3. Locate these two specific folders inside:
* `base_accounting_kit`
* `base_account_budget` (Required dependency)


4. **Copy/Paste** those two folders directly into your `odoo-deployment-stack` folder.

**Structure check for Option B:**

```text
odoo-deployment-stack/
├── base_accounting_kit/
├── base_account_budget/
├── requirements.txt
└── ...

```

### Step 3: Define Python Dependencies

The accounting kit requires specific Python libraries to work (Excel reports, bank statements).

**💻 ON YOUR MAC:**

```bash
# Create or edit your custom requirements file
nano requirements-custom.txt

```

**Paste this content inside:**

```text
# Dependencies for Base Accounting Kit
openpyxl>=3.0.0
ofxparse>=0.21
qifparse>=0.2

```

*Save and exit: `Ctrl+X`, then `Y`, then `Enter`.*

### Step 4: Commit and Push to GitHub

**💻 ON YOUR MAC:**

```bash
# 1. Add all new files (Works for both Option A and B)
git add .

# 2. Commit
git commit -m "Add Accounting Kit and dependencies"

# 3. Push to GitHub
git push origin main

```

---

## 📍 PART 2: Deploy to DigitalOcean Server

Now we pull these changes to your live server.

### Step 5: Pull Changes

**🌊 ON DIGITALOCEAN (SSH in first):**

```bash
# 1. Switch to the Odoo user
sudo su - odoo18

# 2. Go to your custom addons folder
cd /opt/odoo18/odoo18-custom-addons

# 3. Pull the main changes
git pull origin main

# 4. IF YOU CHOSE OPTION A (Submodule), run this to download files:
# (If you chose Option B, you can skip this command)
git submodule update --init --recursive

```

### Step 6: Install Python Dependencies

**🌊 STILL ON DIGITALOCEAN (As `odoo18` user):**

```bash
# 1. Activate the virtual environment
source /opt/odoo18/odoo18-venv/bin/activate

# 2. Install the libraries
pip install -r requirements-custom.txt

# 3. Exit virtual env and odoo user
deactivate
exit

```

### Step 7: Update Odoo Configuration

**🌊 ON DIGITALOCEAN (As your main user, e.g., root):**

```bash
sudo nano /etc/odoo18.conf

```

**⚠️ CRITICAL:** Follow the instruction for your chosen option.

* **If you chose Option A (Submodule):**
You must add the submodule path to `addons_path`.
`addons_path = ..., /opt/odoo18/odoo18-custom-addons/cybro-addons`
* **If you chose Option B (Manual Copy):**
**DO NOTHING.**
Your files are already directly inside `/opt/odoo18/odoo18-custom-addons`, which is already in your config.

*Save and exit: `Ctrl+X`, then `Y`, then `Enter`.*

### Step 8: Restart Odoo

**🌊 ON DIGITALOCEAN:**

```bash
# Restart the service
sudo systemctl restart odoo18

# Check logs to ensure it started clean
sudo tail -f /var/log/odoo18/odoo18.log
# (Ctrl+C to exit)

```

---

## 📍 PART 3: Enable in Odoo Web

**🌐 IN YOUR BROWSER:**

1. **Login** to Odoo as Administrator.
2. **Activate Developer Mode**: Settings → Scroll down → Activate Developer Mode.
3. **Update Apps List**:
* Go to **Apps**.
* Click **Update Apps List** (top menu) → **Update**.


4. **Install**:
* Remove the "Apps" filter.
* Search for: `Full Accounting Kit` (This is the display name for `base_accounting_kit`).
* Click **Activate**.

# Fix: Odoo Addons Path for Manually Copied Modules

## The Problem
In Odoo, the `addons_path` must point to the **folder containing the modules**, not the module folder itself.

* **Current (Wrong):** You are pointing directly to the module folder (e.g., `.../base_accounting_kit`). Odoo looks *inside* that folder for other folders, finds nothing, and gives up.
* **Correction:** You need to point to the **parent folder** (`.../odoo18-custom-addons`), which contains the module.

---

## 🛠️ The Fix

### 1. Edit your configuration file
```bash
sudo nano /etc/odoo18.conf

2. Replace your addons_path block
Delete the old lines pointing to specific modules and use this corrected version:

Ini, TOML

addons_path = /opt/odoo18/odoo/addons,
              /opt/odoo18/odoo18-custom-addons,
              /opt/odoo18/odoo18-custom-addons/account-financial-tools,
              /opt/odoo18/odoo18-custom-addons/reporting-engine

❓ What changed?
Added: /opt/odoo18/odoo18-custom-addons

Reason: This allows Odoo to see base_accounting_kit and base_account_budget, which are sitting directly inside this folder.

Removed: The specific lines for base_account_budget and base_accounting_kit.

Reason: They are now covered by the parent folder added above.

Kept: The lines for account-financial-tools and reporting-engine.

Reason: These are repositories that contain other modules inside them, so they still need to be listed explicitly.

Apply Changes
1. Save and Exit
Press Ctrl+X, then Y, then Enter.

2. Restart Odoo
Bash

sudo systemctl restart odoo18
3. Check in Browser
Refresh Odoo.

Go to Apps → Update Apps List → Update.

Remove the "Apps" filter in the search bar.

Search for "Full Accounting Kit".

It should appear now!