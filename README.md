# intergalactic

Manage a Raspberry Pi fleet (Gen1–Gen5) on **Debian Stable (Trixie)** using a three-phase deployment model:
- **Phase 1: Bootstrap** - Establish secure automation access (local IP)
- **Phase 2: Foundation** - Network connectivity and security foundation (local IP)
- **Phase 3: Production** - Application services (Tailscale network only)

## Three-Phase Deployment Model

This project uses a clean three-phase deployment model that separates concerns and enables network transition from local IP to Tailscale.

### Phase 1: Bootstrap
**Purpose**: Establish secure automation access  
**Connection**: Local IP address (192.168.1.x)  
**User**: `armand` (initial user)  
**Inventory**: `hosts-bootstrap.yml`  
**Roles**: `common_bootstrap`  
**What it does**:
- Creates `ansible` automation user
- Disables password authentication
- Sets up SSH keys
- Minimal, fast, idempotent

### Phase 2: Foundation
**Purpose**: Network connectivity and security foundation  
**Connection**: Local IP address (may require local network)  
**User**: `ansible` (automation user)  
**Inventory**: `hosts-foundation.yml`  
**Roles**: `common`, `ssh_hardening`, `firewall_nftables`, `fail2ban`, `updates`, `tailscale`, `docker_host`, `monitoring_base`  
**What it does**:
- Sets up Tailscale (enables network transition)
- Hardens SSH configuration
- Configures firewall (nftables)
- Sets up fail2ban
- Enables system updates
- Installs Docker engine
- Basic monitoring tools

**Key Feature**: After this phase, the host is on the Tailscale network.

### Phase 3: Production
**Purpose**: Application services and advanced features  
**Connection**: **Tailscale network ONLY** (rigel.tailnet-name.ts.net)  
**User**: `ansible` (automation user)  
**Inventory**: `hosts.yml` (Tailscale hostnames)  
**Roles**: `docker_deploy`, `internal_dns`, `edge_ingress`, `monitoring_docker`, `luks`  
**What it does**:
- Docker deploy user setup
- Internal DNS (CoreDNS)
- Edge ingress (Traefik)
- Advanced monitoring
- LUKS encryption

**Requirement**: MUST connect via Tailscale - fails if not on Tailscale network.

### Network Transition

The three-phase model enables a clean transition from local network to Tailscale:

1. **Bootstrap** → Uses local IP, creates automation user
2. **Foundation** → Uses local IP, sets up Tailscale
3. **Production** → Uses Tailscale hostname, deploys services

After Foundation completes, update `hosts.yml` with the Tailscale hostname, then run Production.

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
cp all_secrets.yml.example all_secrets.yml
```

#### 4.2: Edit the Secrets File

Open `all_secrets.yml` in your text editor and fill in your actual values:

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

#### 6.1: Edit ansible/inventories/prod/hosts-bootstrap.yml

Open `ansible/inventories/prod/hosts-bootstrap.yml` and update the IP address and initial user:

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
- This file is only used during bootstrap - the script automatically selects it

#### 6.2: Edit ansible/inventories/prod/hosts.yml (Production Inventory)

The production inventory (`hosts.yml`) should use the `ansible` automation user for all hosts that have been bootstrapped:

```yaml
all:
  children:
    home_milkyway:
      children:
        rpi4:
          hosts:
            rigel:
              ansible_host: 192.168.1.40
              ansible_user: ansible  # Automation user (after bootstrap)
```

**Note**: The `run-ansible.sh` script automatically uses:
- `hosts-bootstrap.yml` for bootstrap playbooks (e.g., `rigel-bootstrap`)
- `hosts.yml` for regular playbooks (e.g., `rigel`)

**How to find your Pi's IP address:**
- If connected via Ethernet: Check your router's admin page
- If using WiFi: The Pi will get an IP via DHCP - check your router
- You can also scan your network: `nmap -sn 192.168.1.0/24`
- Or SSH into the Pi and run: `hostname -I`

### Step 7: Phase 1 - Run Bootstrap

**CRITICAL**: The bootstrap process will **immediately disable password-based SSH authentication**. Make sure:
1. Your SSH key works for your existing user (you can SSH in without a password)
2. Your automation SSH key is in `all_secrets.yml`
3. Your personal SSH key is in `all_secrets.yml` (for your user account)

```bash
cd ~/Documents/GitHub/intergalactic

# Run Phase 1: Bootstrap (replace 'rigel' with your hostname)
./scripts/run-ansible.sh prod rigel bootstrap
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
- The bootstrap inventory (`hosts-bootstrap.yml`) uses your initial user
- The production inventory (`hosts.yml`) uses the `ansible` user - make sure it's configured correctly

### Step 8: Phase 2 - Run Foundation

This sets up network connectivity, security, and base infrastructure.

```bash
# Run Phase 2: Foundation (replace 'rigel' with your hostname)
./scripts/run-ansible.sh prod rigel foundation
```

**What this does:**
- Applies complete SSH hardening configuration
- Sets up firewall (nftables) with default-deny policy
- Configures fail2ban (optional, enabled by default)
- Installs and configures Tailscale (enables network transition)
- Installs Docker engine
- Sets up automatic security updates
- Configures system hardening (sysctl, etc.)
- Basic monitoring tools

**After Foundation completes:**
The playbook will display the Tailscale hostname. Update `hosts.yml` with this hostname before running Production.

### Step 9: Phase 3 - Run Production

**CRITICAL**: Production phase **requires Tailscale connection**. Update `hosts.yml` with Tailscale hostname first.

```bash
# 1. Update hosts.yml with Tailscale hostname (from foundation output)
#    rigel:
#      ansible_host: rigel.tailnet-name.ts.net  # Or just "rigel" with MagicDNS
#      ansible_user: ansible

# 2. Run Phase 3: Production
./scripts/run-ansible.sh prod rigel production
```

**What this does:**
- Sets up Docker deploy user
- Deploys internal DNS (CoreDNS)
- Deploys edge ingress (Traefik)
- Advanced monitoring tools
- LUKS encryption (if configured)

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

**Note**: The script automatically uses the production inventory (`hosts.yml`) which uses the `ansible` user. Make sure your host is configured in `hosts.yml` with `ansible_user: ansible` after bootstrap completes.

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

- **Check**: Your SSH public key is correctly in `all_secrets.yml`
- **Check**: The bootstrap playbook ran successfully
- **Check**: You're using the correct user (`ansible` for automation, your username for personal)
- **Try**: `ssh -v ansible@192.168.1.40` to see detailed error messages
- **Try**: Verify your key is on the Pi: `ssh armand@192.168.1.40 "cat ~/.ssh/authorized_keys"`

### Ansible playbook fails with "authentication required"

- **Check**: You can SSH into the Pi manually with your existing user
- **Check**: Your existing user has sudo access: `ssh armand@192.168.1.40 "sudo whoami"`
- **Check**: The bootstrap playbook ran successfully first
- **Check**: `ansible_user` in `hosts-bootstrap.yml` matches your existing username (for bootstrap)
- **Check**: `ansible_user` in `hosts.yml` is set to `ansible` (for regular operations)
- **Try**: Run bootstrap again: `./scripts/run-ansible.sh prod rigel-bootstrap`

### Password authentication still works after bootstrap

- **Check**: SSH service was restarted: `ssh armand@192.168.1.40 "sudo systemctl status ssh"`
- **Check**: Bootstrap playbook completed successfully
- **Try**: Manually verify: `ssh armand@192.168.1.40 "sudo grep PasswordAuthentication /etc/ssh/sshd_config.d/*"`
- **Try**: Restart SSH manually: `ssh armand@192.168.1.40 "sudo systemctl restart ssh"`

### Tailscale not connecting

- **Check**: `tailscale_authkey` is set in `all_secrets.yml` (not empty, not placeholder)
- **Check**: The auth key is still valid (they expire)
- **Check**: Firewall allows UDP port 41641 (should be automatic)
- **Try**: SSH into Pi and run `sudo tailscale status` to see error messages

### Can't SSH into Pi after bootstrap

- **Check**: Your SSH keys are correctly configured in `all_secrets.yml`
- **Check**: You're using the correct username (`ansible` or your personal username)
- **Check**: Your SSH key is in your local `~/.ssh/` directory
- **Try**: Test with verbose output: `ssh -v ansible@192.168.1.40`
- **Try**: Verify key is authorized: `ssh armand@192.168.1.40 "sudo cat /home/ansible/.ssh/authorized_keys"`

### "Host key checking" errors

- **Fix**: Remove old host key: `ssh-keygen -R 192.168.1.40`
- **Note**: The bootstrap playbooks automatically fetch and add host keys using `ssh-keyscan` for secure verification
- **Security**: Host key checking is enabled by default to prevent MITM attacks. Do NOT disable it.

### Can't find Raspberry Pi on network

- **Check**: Pi is powered on and has Ethernet/WiFi connected
- **Check**: Pi and your computer are on the same network
- **Try**: Scan network: `nmap -sn 192.168.1.0/24` (adjust subnet)
- **Try**: Check router admin page for connected devices

---

## Quick Reference

### Common Commands

```bash
# Phase 1: Bootstrap (initial access setup)
./scripts/run-ansible.sh prod <hostname> bootstrap

# Phase 2: Foundation (network + security)
./scripts/run-ansible.sh prod <hostname> foundation

# Phase 3: Production (application services)
./scripts/run-ansible.sh prod <hostname> production

# Migrate existing host to three-phase structure
./scripts/migrate-to-three-phase.sh <hostname> [tailscale-hostname]

# SSH into Pi with ansible user (local IP)
ssh -i ~/.ssh/intergalactic_ansible ansible@<pi-ip-address>

# SSH into Pi via Tailscale (after foundation)
ssh -i ~/.ssh/intergalactic_ansible ansible@<hostname>.tailnet-name.ts.net
```

### File Locations

- **Secrets**: `ansible/inventories/prod/group_vars/all_secrets.yml` (SSH keys, Tailscale key, Hostinger API token)
- **Bootstrap inventory**: `ansible/inventories/prod/hosts-bootstrap.yml` (Phase 1: local IP, armand user)
- **Foundation inventory**: `ansible/inventories/prod/hosts-foundation.yml` (Phase 2: local IP, ansible user)
- **Production inventory**: `ansible/inventories/prod/hosts.yml` (Phase 3: Tailscale hostname, ansible user)
- **General config**: `ansible/inventories/prod/group_vars/all.yml` (global settings)
- **Host-specific config**: `ansible/inventories/prod/host_vars/<hostname>.yml` (per-host overrides)

---

## Best-Practice Identities

- **Automation account**: `ansible` (SSH key only, sudo via become, NOPASSWD)
- **Human account(s)**: Separate from automation for clear audit trails
- **Deployment account**: `deploy` (if `enable_docker_deploy: true` - SSH key only, docker group, passwordless sudo, owns `/srv/` directory)

## Security Non-Negotiables

- No password-based login ever (SSH keys only)
- Tight SSH allowlist
- Default-deny firewall; only explicitly allowed ports
- Fail2ban: optional but recommended - detects invalid user attempts and reconnaissance even with key-only auth; long/"forever" bans + IP log (configurable via `enable_fail2ban`)
- Minimal packages; no X/desktop on headless nodes (desktop only on Gen5 workstation)

### Fail2ban Configuration

Fail2ban is **enabled by default** and provides valuable security intelligence even with password authentication disabled. It detects:

- Invalid user attempts (e.g., trying `root`, `admin`, non-existent users)
- Wrong SSH key attempts (valid user, wrong key)
- Reconnaissance and scanning activity
- Logs all offenders to `/var/log/intergalactic/fail2ban-offenders.log`

**Configuration options** (in `ansible/inventories/prod/group_vars/all.yml`):

```yaml
enable_fail2ban: true  # Set to false to disable fail2ban entirely
fail2ban_maxretry: 5   # Failed attempts before ban (default: 5, was 2)
fail2ban_bantime_seconds: 315360000  # Ban duration (~10 years, effectively permanent)
```

**Why keep fail2ban with key-only auth?**
- **Defense in depth**: Additional security layer
- **Security intelligence**: See who's probing your systems
- **Misconfiguration protection**: Detects if password auth is accidentally re-enabled
- **Low overhead**: Minimal resource usage
- **Industry standard**: Common in hardened production environments

**To disable fail2ban:**
Set `enable_fail2ban: false` in `ansible/inventories/prod/group_vars/all.yml` or in host-specific vars.

---

### Encrypted Home Directories

For systems requiring encrypted user data, this setup supports encrypted home directories with automatic boot capability.

#### Architecture

**Partition Layout:**
- `/dev/nvme0n1p1` → `/boot` (512MB, FAT32, unencrypted)
- `/dev/nvme0n1p2` → `/` (32GB recommended, ext4, unencrypted)
  - Contains `/etc/ssh/authorized_keys.d/` (SSH keys - unencrypted, accessible at boot)
- `/dev/nvme0n1p3` → `/home` (Remaining space, LUKS encrypted, mounted after boot)

**Boot Sequence:**
1. Root filesystem mounts (unencrypted) → SSH keys available immediately
2. SSH daemon starts → Authentication works (keys on unencrypted root)
3. Tailscale connects → System fully operational
4. User SSHs in remotely → Unlocks encrypted `/home` partition
5. `/home` mounts → User directories available

#### Configuration

**1. Enable encrypted home in host_vars:**

Edit `ansible/inventories/prod/host_vars/<hostname>.yml`:
```yaml
enable_luks: true
luks_encrypt_home: true
luks_home_device: "/dev/nvme0n1p3"  # Set after identifying partition
```

**2. Add passphrase to secrets:**

Edit `ansible/inventories/prod/group_vars/all_secrets.yml`:
```yaml
# Generate base64-encoded passphrase:
# Generate 64-character base64 string (48 bytes entropy):
# openssl rand -base64 48 | head -c 64
# Or: echo -n "your-long-passphrase" | base64 (ensure 64+ chars)
luks_home_passphrase: "dGhpcyBpcyBhIHNhbXBsZSBwYXNzcGhyYXNlIGluIGJhc2U2NA=="
```

**3. Bootstrap and setup:**

```bash
# Bootstrap (creates ansible user, sets up SSH keys in system location)
./scripts/run-ansible.sh prod <hostname>-bootstrap

# Normal setup (installs cryptsetup, shows encryption instructions)
./scripts/run-ansible.sh prod <hostname>
```

**4. Encrypt home partition:**

After identifying the partition with `lsblk` or `fdisk -l`:

```bash
# Option A: Use helper script
./scripts/encrypt-home-partition.sh /dev/nvme0n1p3 "<base64-passphrase>"

# Option B: Manual encryption
echo -n "<base64-passphrase>" | base64 -d | sudo cryptsetup luksFormat /dev/nvme0n1p3 -
sudo cryptsetup open /dev/nvme0n1p3 home-crypt
sudo mkfs.ext4 /dev/mapper/home-crypt
sudo cryptsetup close home-crypt
```

**5. Configure mounting:**

Run the playbook again - it will automatically configure `/etc/crypttab` and `/etc/fstab`:
```bash
./scripts/run-ansible.sh prod <hostname>
```

**6. Test unlock:**

After reboot, SSH in and unlock:
```bash
ssh ansible@<host-ip>
sudo cryptsetup open /dev/nvme0n1p3 home-crypt
# Enter passphrase when prompted
sudo mount /home
ls -la /home  # Should show user directories
```

#### Security Considerations

- **SSH Keys**: Stored in `/etc/ssh/authorized_keys.d/` on unencrypted root (required for boot-time authentication)
- **Home Data**: Fully encrypted with LUKS, unlocked remotely after boot
- **Passphrase**: Base64-encoded in `all_secrets.yml` (gitignored), decoded only during encryption
- **Trade-off**: Root filesystem unencrypted (required for automatic boot), but user data is protected

#### Partition Sizing Recommendations

For a **250GB NVMe drive**:
- **Boot (512MB)**: Standard for Raspberry Pi, holds kernel/initramfs
- **Root (64GB)**: Recommended for desktop + Docker systems. Provides headroom for:
  - Debian base + desktop (~8-10GB)
  - Docker images/containers (10-20GB+)
  - System packages and updates (~10-15GB)
  - Logs, temp files, and buffer (~10GB)
- **Home (~185GB)**: All user data encrypted, typically largest partition

For smaller drives or minimal systems, 32-48GB root may suffice, but 64GB is recommended for desktop + Docker workloads.

---

## Verification and Testing

### Verify Encrypted Home Setup

Before deploying encrypted home directories, verify the implementation:

```bash
./scripts/verify-encrypted-home-setup.sh
```

This script checks:
- SSH configuration has `AuthorizedKeysFile` directive
- System SSH keys directory is created
- Keys are written to system location (not home directories)
- **docker_deploy**: Sets up a `deploy` user for Docker container deployment. Creates user with SSH access (using same keys as `armand`), configures `/srv/` directory, installs git, sets up passwordless sudo, and optionally configures Docker daemon DNS and environment variables. Enable with `enable_docker_deploy: true` in host_vars.
- **LUKS**: Encrypted home partition support with automatic boot capability
- Configuration files are properly set up
- Helper script exists and is executable
- Documentation is complete
- YAML syntax is valid

**Expected output:**
```
✓ VERIFICATION PASSED: All checks passed
```

### Verify Inventory Users

Ensure all hosts use correct users in inventory files:

```bash
./scripts/verify-inventory-users.sh
```

This verifies:
- Bootstrap inventory: All hosts use `ansible_user: armand`
- Production inventory: All hosts use `ansible_user: ansible`
- All hosts are present in both inventories

---

## Re-configuring Existing Hosts

If you have hosts that were previously configured with the old single-phase approach, you should re-configure them using the new three-phase structure. This ensures all hosts follow the same architecture and are in a known good state.

**Recommended Approach:**

1. **If the host already has Tailscale:**
   - Get Tailscale hostname: `tailscale status | grep <hostname>`
   - Update `hosts.yml` with Tailscale hostname
   - Run production phase: `./scripts/run-ansible.sh prod <hostname> production`

2. **If the host doesn't have Tailscale yet:**
   - Ensure host is accessible via local IP
   - Update `hosts-foundation.yml` with local IP and `ansible_user: ansible`
   - Run foundation phase: `./scripts/run-ansible.sh prod <hostname> foundation`
   - Update `hosts.yml` with Tailscale hostname (from foundation output)
   - Run production phase: `./scripts/run-ansible.sh prod <hostname> production`

**Note:** The three-phase playbooks are idempotent, so re-running them is safe and will ensure your hosts match the current configuration.

## Next Steps

Once your first Pi is set up:

1. **Add more Pis**: 
   - Install standard Raspberry Pi image on each new Pi
   - Ensure you can SSH in with your existing user
   - Add the new Pi to `ansible/inventories/prod/hosts-bootstrap.yml` (with initial user)
   - Run Phase 1: `./scripts/run-ansible.sh prod <new-hostname> bootstrap`
   - Add the new Pi to `ansible/inventories/prod/hosts-foundation.yml` (with local IP, ansible user)
   - Run Phase 2: `./scripts/run-ansible.sh prod <new-hostname> foundation`
   - Update `ansible/inventories/prod/hosts.yml` with Tailscale hostname (from foundation output)
   - Run Phase 3: `./scripts/run-ansible.sh prod <new-hostname> production`

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