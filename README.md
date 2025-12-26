# intergalactic

Manage a Raspberry Pi fleet (Gen1–Gen5) on **Debian Stable (Trixie)** using:
- **Bootstrap**: Create ansible user, disable password authentication, set up SSH keys
- **Ansible**: Full configuration (firewall, SSH hardening, Tailscale, Docker, etc.)

## Prerequisites

- **Docker** installed and running (this is the only requirement)
- **Raspberry Pi** with standard Debian/Raspberry Pi OS image already installed and booted
- **SSH access** to your Pi using your existing user account (e.g., `armand`)
- Your existing user has **sudo access** on the Pi
- **Python 3** (usually pre-installed on macOS/Linux)

---

## Complete First-Time Setup Guide

This guide assumes:
- You have a **standard Raspberry Pi image** already installed and booted
- You can **SSH into the Pi** using your existing user (e.g., `armand`) with your SSH key
- Your existing user has a **password set** (which we will disable for SSH)
- You have **never used Ansible or Tailscale before**

**Important**: The bootstrap process will **immediately disable password-based SSH authentication** for security. Make sure your SSH keys are properly configured before proceeding!

### Step 1: Clone the Repository

```bash
# If you haven't already, clone or download this repository
cd ~/Documents/GitHub  # or wherever you want it
git clone <repository-url> intergalactic
cd intergalactic
```

### Step 2: Generate SSH Keys

You need SSH keys to authenticate with your Raspberry Pi. We'll create a dedicated key for automation.

#### 2.1: Generate the Automation SSH Key

```bash
# Generate a new SSH key pair (press Enter to accept defaults, no passphrase needed)
ssh-keygen -t ed25519 -f ~/.ssh/intergalactic_ansible -C "ansible@control"

# This creates two files:
# - ~/.ssh/intergalactic_ansible (private key - keep secret!)
# - ~/.ssh/intergalactic_ansible.pub (public key - we'll use this)
```

#### 2.2: Generate Your Personal SSH Key (if you don't have one)

```bash
# Generate a personal SSH key (if you don't already have one)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "your-email@example.com"

# Or use an existing key if you have one
```

#### 2.3: Get Your Public Keys

```bash
# Display your automation public key (copy this entire line)
cat ~/.ssh/intergalactic_ansible.pub

# Display your personal public key (copy this entire line)
cat ~/.ssh/id_ed25519.pub
```

**Important**: Copy both public keys - you'll need them in Step 4.

### Step 3: Get Tailscale Auth Key (Optional but Recommended)

Tailscale provides secure VPN access to your Raspberry Pi. If you want to use it:

#### 3.1: Create a Tailscale Account

1. Go to https://tailscale.com/
2. Sign up for a free account (or sign in if you have one)

#### 3.2: Create an Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Click **"Generate auth key"**
3. Give it a name like "intergalactic-rpi-fleet"
4. Set **Reusable**: Yes (if you want to use it for multiple Pis)
5. Set **Ephemeral**: No (for persistent devices)
6. Click **"Generate key"**
7. **Copy the key immediately** - it looks like `tskey-auth-xxxxxxxxxxxxx`

**Important**: This key is only shown once! Save it securely.

**Note**: If you don't want to use Tailscale, you can skip this step and set `enable_tailscale: false` in `ansible/inventories/prod/group_vars/all.yml` later.

### Step 4: Configure Secrets File

The secrets file stores your SSH keys and Tailscale auth key. It's gitignored (never committed to the repository).

#### 4.1: Create the Secrets File

```bash
cd ansible/inventories/prod/group_vars
cp all.secrets.yml.example all.secrets.yml
```

#### 4.2: Edit the Secrets File

Open `all.secrets.yml` in your text editor and fill in your actual values:

```yaml
---
# SSH public keys for the automation user (ansible)
automation_authorized_keys:
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... YOUR_AUTOMATION_KEY_HERE ansible@control"
  # Paste your automation public key from Step 2.3 here
  # It should start with "ssh-ed25519" and end with "ansible@control"

# Human user accounts with their SSH public keys
human_users:
  - name: your-username
    authorized_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... YOUR_PERSONAL_KEY_HERE your-email@example.com"
      # Paste your personal public key from Step 2.3 here
      # Change "your-username" to your actual username

# Tailscale authentication key (from Step 3.2)
tailscale_authkey: "tskey-auth-xxxxxxxxxxxxx"
# Paste your Tailscale auth key here (or leave empty if not using Tailscale)
```

**Example** (with real-looking values):

```yaml
---
automation_authorized_keys:
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdYrr6ERlcqtG9507wmbYogvoh4WvDgFTOhjZ74QDFK ansible@control"

human_users:
  - name: alice
    authorized_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJOHNDOE1234567890abcdef alice@laptop"

tailscale_authkey: "tskey-auth-abc123xyz789"
```

**Important**: 
- Replace `your-username` with your actual Linux username (e.g., `alice`, `bob`)
- Make sure the SSH keys are complete (they're long single lines)
- If not using Tailscale, set `tailscale_authkey: ""` (empty string)

### Step 5: Verify Your Pi is Accessible

Before proceeding, make sure you can SSH into your Raspberry Pi with your existing user.

```bash
# Test SSH access (replace with your Pi's IP and username)
ssh armand@192.168.1.40

# You should be able to login without a password (using your SSH key)
# Once logged in, verify you have sudo access:
sudo whoami
# Should output: root

# Exit the Pi
exit
```

**Important**: 
- If you can't SSH in, fix that first before proceeding
- If you need a password to SSH, make sure your SSH key is in `~/.ssh/authorized_keys` on the Pi
- The bootstrap process will disable password authentication, so SSH key access is required

### Step 6: Configure Ansible Inventory

Tell Ansible where your Raspberry Pi will be on the network.

#### 6.1: Edit ansible/inventories/prod/hosts.yml

Open `ansible/inventories/prod/hosts.yml` and update the IP address and initial user:

```yaml
all:
  children:
    home_milkyway:
      children:
        rpi4:
          hosts:
            rigel:  # Change to your hostname
              ansible_host: 192.168.1.40  # CHANGE THIS to your Pi's IP address
              ansible_user: armand  # CHANGE THIS to your existing username (e.g., armand)
```

**Important**: 
- Set `ansible_user` to your **existing username** (the one you use to SSH in now)
- This user must have **sudo access** (passwordless sudo is preferred, but password sudo will work)
- After bootstrap completes, Ansible will use the `ansible` user for future runs

**How to find your Pi's IP address:**
- If connected via Ethernet: Check your router's admin page
- If using WiFi: The Pi will get an IP via DHCP - check your router
- You can also scan your network: `nmap -sn 192.168.1.0/24`
- Or SSH into the Pi and run: `hostname -I`

### Step 7: Run Ansible Bootstrap

**CRITICAL**: The bootstrap process will **immediately disable password-based SSH authentication**. Make sure:
1. Your SSH key works for your existing user (you can SSH in without a password)
2. Your automation SSH key is in `all.secrets.yml`
3. Your personal SSH key is in `all.secrets.yml` (for your user account)

```bash
cd ~/Documents/GitHub/intergalactic

# Run the bootstrap playbook (replace 'rigel' with your hostname)
./scripts/run-ansible.sh prod rigel-bootstrap
```

**What this does:**
- **IMMEDIATELY disables password authentication** for SSH (security hardening)
- Installs required packages (sudo, python3, etc.)
- Creates the `ansible` automation user
- Adds your automation SSH key to the `ansible` user
- Adds your personal SSH key to your existing user account
- Sets up passwordless sudo for the `ansible` user
- Sets hostname (if configured)

**Expected output:**
```
PLAY [Bootstrap Rigel (create ansible user, disable password auth, set up keys)] **
...
TASK [common_bootstrap : Immediately disable password authentication] **********
changed: [rigel]

TASK [common_bootstrap : Restart SSH service to apply password disable] *******
changed: [rigel]

TASK [common_bootstrap : Ensure automation user exists] **********************
changed: [rigel]

...
PLAY RECAP ******************************************************************
rigel                      : ok=10   changed=7    unreachable=0    failed=0
```

**Important Notes:**
- After this step, **password-based SSH is disabled** - only SSH keys will work
- If bootstrap fails, you can still SSH in with your existing user/key to troubleshoot
- The `ansible` user is now created and ready for automation

### Step 8: Run Main Ansible Playbook

This applies the full configuration: firewall, SSH hardening, Tailscale, Docker, etc.

```bash
# For a headless Pi (like rigel):
./scripts/run-ansible.sh prod rigel

# For a workstation Pi with desktop (like vega):
./scripts/run-ansible.sh prod vega-desktop
```

**What this does:**
- Applies complete SSH hardening configuration
- Sets up firewall (nftables) with default-deny policy
- Configures fail2ban (bans IPs after failed login attempts)
- Installs and configures Tailscale (if enabled)
- Installs Docker (if enabled)
- Sets up automatic security updates
- Configures system hardening (sysctl, etc.)
- And more...

**Expected output:**
```
PLAY [Rigel (RPi4 headless endpoint + docker host)] ***********************
...
TASK [ssh_hardening : Configure sshd drop-in] ******************************
changed: [rigel]

TASK [firewall_nftables : Deploy nftables rules] **************************
changed: [rigel]

...
PLAY RECAP ******************************************************************
rigel                      : ok=45   changed=12   unreachable=0    failed=0
```

**This may take 5-10 minutes** depending on your internet connection (it downloads packages).

**Note**: After this step, Ansible will use the `ansible` user for all future runs (no need to specify `ansible_user` in inventory).

### Step 9: Verify Everything Works

#### 9.1: Test SSH Access with Ansible User

```bash
# SSH into your Pi using the ansible user
ssh ansible@192.168.1.40

# You should be able to login without a password (using your automation SSH key)
# Try running a command:
sudo docker ps
exit
```

#### 9.2: Test SSH Access with Your User

```bash
# SSH into your Pi using your personal user
ssh armand@192.168.1.40

# You should be able to login without a password (using your personal SSH key)
# Password authentication should be disabled - try it:
# (This should fail - password auth is disabled)
exit
```

#### 9.3: Test Tailscale (if enabled)

1. Go to https://login.tailscale.com/admin/machines
2. You should see your Raspberry Pi listed
3. You can now access it via Tailscale IP from anywhere

#### 9.4: Test Docker (if enabled)

```bash
ssh ansible@192.168.1.40
docker run hello-world
# Should see "Hello from Docker!" message
exit
```

---

## Troubleshooting

### "Permission denied" when SSH'ing

- **Check**: Your SSH public key is correctly in `all.secrets.yml`
- **Check**: The bootstrap playbook ran successfully
- **Check**: You're using the correct user (`ansible` for automation, your username for personal)
- **Try**: `ssh -v ansible@192.168.1.40` to see detailed error messages
- **Try**: Verify your key is on the Pi: `ssh armand@192.168.1.40 "cat ~/.ssh/authorized_keys"`

### Ansible playbook fails with "authentication required"

- **Check**: You can SSH into the Pi manually with your existing user
- **Check**: Your existing user has sudo access: `ssh armand@192.168.1.40 "sudo whoami"`
- **Check**: The bootstrap playbook ran successfully first
- **Check**: `ansible_user` in `hosts.yml` matches your existing username (before bootstrap)
- **Try**: Run bootstrap again: `./scripts/run-ansible.sh prod rigel-bootstrap`

### Password authentication still works after bootstrap

- **Check**: SSH service was restarted: `ssh armand@192.168.1.40 "sudo systemctl status ssh"`
- **Check**: Bootstrap playbook completed successfully
- **Try**: Manually verify: `ssh armand@192.168.1.40 "sudo grep PasswordAuthentication /etc/ssh/sshd_config.d/*"`
- **Try**: Restart SSH manually: `ssh armand@192.168.1.40 "sudo systemctl restart ssh"`

### Tailscale not connecting

- **Check**: `tailscale_authkey` is set in `all.secrets.yml` (not empty, not placeholder)
- **Check**: The auth key is still valid (they expire)
- **Check**: Firewall allows UDP port 41641 (should be automatic)
- **Try**: SSH into Pi and run `sudo tailscale status` to see error messages

### Can't SSH into Pi after bootstrap

- **Check**: Your SSH keys are correctly configured in `all.secrets.yml`
- **Check**: You're using the correct username (`ansible` or your personal username)
- **Check**: Your SSH key is in your local `~/.ssh/` directory
- **Try**: Test with verbose output: `ssh -v ansible@192.168.1.40`
- **Try**: Verify key is authorized: `ssh armand@192.168.1.40 "sudo cat /home/ansible/.ssh/authorized_keys"`

### "Host key checking" errors

- **Fix**: Remove old host key: `ssh-keygen -R 192.168.1.40`
- **Or**: Edit `ansible/ansible.cfg` and set `host_key_checking = False` (less secure)

### Can't find Raspberry Pi on network

- **Check**: Pi is powered on and has Ethernet/WiFi connected
- **Check**: Pi and your computer are on the same network
- **Try**: Scan network: `nmap -sn 192.168.1.0/24` (adjust subnet)
- **Try**: Check router admin page for connected devices

---

## Quick Reference

### Common Commands

```bash
# Run Ansible bootstrap (creates ansible user, disables password auth)
./scripts/run-ansible.sh prod <hostname>-bootstrap

# Run main Ansible playbook (full configuration)
./scripts/run-ansible.sh prod <hostname>

# Run desktop playbook (for workstations)
./scripts/run-ansible.sh prod <hostname>-desktop

# SSH into Pi with ansible user
ssh ansible@<pi-ip-address>

# SSH into Pi with your personal user
ssh <your-username>@<pi-ip-address>
```

### File Locations

- **Secrets**: `ansible/inventories/prod/group_vars/all.secrets.yml` (SSH keys, Tailscale key)
- **Ansible inventory**: `ansible/inventories/prod/hosts.yml` (IP addresses, initial user)
- **General config**: `ansible/inventories/prod/group_vars/all.yml` (global settings)
- **Host-specific config**: `ansible/inventories/prod/host_vars/<hostname>.yml` (per-host overrides)

---

## Best-Practice Identities

- **Automation account**: `ansible` (SSH key only, sudo via become, NOPASSWD)
- **Human account(s)**: Separate from automation for clear audit trails

## Security Non-Negotiables

- No password-based login ever (SSH keys only)
- Tight SSH allowlist
- Default-deny firewall; only explicitly allowed ports
- Fail2ban: treat password attempts as hostile; long/"forever" bans + IP log
- Minimal packages; no X/desktop on headless nodes (desktop only on Gen5 workstation)

---

## Next Steps

Once your first Pi is set up:

1. **Add more Pis**: 
   - Install standard Raspberry Pi image on each new Pi
   - Ensure you can SSH in with your existing user
   - Add the new Pi to `ansible/inventories/prod/hosts.yml`
   - Run bootstrap: `./scripts/run-ansible.sh prod <new-hostname>-bootstrap`
   - Run main playbook: `./scripts/run-ansible.sh prod <new-hostname>`

2. **Customize**: Edit `ansible/inventories/prod/group_vars/all.yml` for global settings

3. **Host-specific**: Edit `ansible/inventories/prod/host_vars/<hostname>.yml` for per-host settings

4. **Update**: Run playbooks again to apply changes: `./scripts/run-ansible.sh prod <hostname>`

---

## Support

If you encounter issues not covered here:

1. Check the troubleshooting section above
2. Review Ansible output for specific error messages
3. Check Pi logs: `ssh ansible@<pi-ip> "sudo journalctl -xe"`
4. Verify all configuration files are correctly formatted (YAML syntax)
