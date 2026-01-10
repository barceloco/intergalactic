# intergalactic

Manage a Raspberry Pi fleet (Gen1–Gen5) on **Debian Stable (Trixie)** using a three-phase deployment model.

**See [scripts/README.md](scripts/README.md) for documentation on all utility scripts.**
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
**Inventory**: `hosts-production.yml` (Tailscale hostnames)  
**Roles**: `docker_deploy`, `internal_dns`, `edge_ingress`, `monitoring_docker`, `luks`  
**What it does**:
- Docker deploy user setup and directory structure
- Docker data-root configuration (`/home/deploy/docker`)
- Internal DNS (CoreDNS)
- Edge ingress (Traefik)
- Advanced monitoring
- LUKS/cryptsetup (for external encrypted devices)
- Samba file sharing (if enabled)
- Desktop environment (if enabled)

**Requirement**: MUST connect via Tailscale - fails if not on Tailscale network.

### Network Transition

The three-phase model enables a clean transition from local network to Tailscale:

1. **Bootstrap** → Uses local IP, creates automation user
2. **Foundation** → Uses local IP, sets up Tailscale
3. **Production** → Uses Tailscale hostname, deploys services

After Foundation completes, update `hosts-production.yml` with the Tailscale hostname, then run Production.

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

#### 3.3: Get Hostinger API Token (Optional, for Edge Ingress)

If you plan to use the `edge_ingress` role (Traefik with HTTPS), you'll need a Hostinger DNS API token for ACME DNS-01 challenges:

1. Go to https://hpanel.hostinger.com/api
2. Generate an API token
3. **Copy the token** - you'll need it in Step 4

**Note**: This is only needed if `edge_ingress_enabled: true` for a host. You can skip this if not using Traefik.

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

# Hostinger DNS API token (from Step 3.3, optional)
# Get your API token from: https://hpanel.hostinger.com/api
# Only needed if edge_ingress_enabled is true for a host
hostinger_api_token: "Hostinger_API_Key_here"
# Paste your Hostinger API token here (or leave empty if not using edge ingress)
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

#### 6.2: Edit ansible/inventories/prod/hosts-production.yml (Production Inventory)

The production inventory (`hosts-production.yml`) should use the `ansible` automation user for all hosts that have been bootstrapped:

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
- `hosts-production.yml` for regular playbooks (e.g., `rigel`)

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
- The production inventory (`hosts-production.yml`) uses the `ansible` user - make sure it's configured correctly

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
The playbook will display the Tailscale hostname. Update `hosts-production.yml` with this hostname before running Production.

### Step 9: Phase 3 - Run Production

**CRITICAL**: Production phase **requires Tailscale connection**. Update `hosts-production.yml` with Tailscale hostname first.

```bash
# 1. Update hosts-production.yml with Tailscale hostname (from foundation output)
#    rigel:
#      ansible_host: rigel.tailnet-name.ts.net  # Or just "rigel" with MagicDNS
#      ansible_user: ansible

# 2. Run Phase 3: Production
./scripts/run-ansible.sh prod rigel production
```

**What this does:**
- Sets up Docker deploy user and directory structure
- Configures Docker data-root to `/home/deploy/docker` (on data partition)
- Sets up bind mounts: `/srv` → `/home/deploy/srv`, `/var/log/apps` → `/home/deploy/logs/apps`
- Deploys internal DNS (CoreDNS)
- Deploys edge ingress (Traefik)
- Advanced monitoring tools
- LUKS/cryptsetup (for mounting external encrypted devices)

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

**Note**: The script automatically uses the production inventory (`hosts-production.yml`) which uses the `ansible` user. Make sure your host is configured in `hosts-production.yml` with `ansible_user: ansible` after bootstrap completes.

### Step 10: Verify Everything Works

#### 10.1: Test SSH Access with Ansible User

```bash
# SSH into your Pi using the ansible user
ssh ansible@192.168.1.40

# You should be able to login without a password (using your automation SSH key)
# Try running a command:
sudo docker ps
exit
```

#### 10.2: Test SSH Access with Your User

```bash
# SSH into your Pi using your personal user
ssh armand@192.168.1.40

# You should be able to login without a password (using your personal SSH key)
# Password authentication should be disabled - try it:
# (This should fail - password auth is disabled)
exit
```

#### 10.3: Test Tailscale (if enabled)

1. Go to https://login.tailscale.com/admin/machines
2. You should see your Raspberry Pi listed
3. You can now access it via Tailscale IP from anywhere

#### 10.4: Test Docker (if enabled)

```bash
ssh ansible@192.168.1.40
docker run hello-world
# Should see "Hello from Docker!" message
exit
```

---

## Troubleshooting

### "Permission denied" when SSH'ing

**Symptoms**: Cannot SSH into the Pi, getting "Permission denied (publickey)"

**Diagnosis**:
1. **Check SSH key configuration**:
   ```bash
   # Verify key is in all_secrets.yml
   cat ansible/inventories/prod/group_vars/all_secrets.yml | grep -A 5 "automation_authorized_keys"
   ```

2. **Check key file exists locally**:
   ```bash
   ls -la ~/.ssh/intergalactic_ansible
   ```

3. **Test SSH connection with verbose output**:
   ```bash
   ssh -v -i ~/.ssh/intergalactic_ansible ansible@192.168.1.40
   ```

4. **Verify key is on the Pi**:
   ```bash
   ssh armand@192.168.1.40 "sudo cat /etc/ssh/authorized_keys.d/ansible"
   ```

**Solutions**:
- Ensure SSH key is in `all_secrets.yml` under `automation_authorized_keys`
- Verify you're using the correct user (`ansible` for automation, `armand` for personal)
- Check bootstrap playbook ran successfully
- Verify SSH key file permissions: `chmod 600 ~/.ssh/intergalactic_ansible`

### Ansible playbook fails with "authentication required"

**Symptoms**: Playbook fails with authentication errors

**Diagnosis**:
1. **Test manual SSH access**:
   ```bash
   ssh armand@192.168.1.40
   ```

2. **Check sudo access**:
   ```bash
   ssh armand@192.168.1.40 "sudo whoami"
   # Should output: root
   ```

3. **Verify inventory configuration**:
   ```bash
   # For bootstrap
   cat ansible/inventories/prod/hosts-bootstrap.yml | grep ansible_user
   # Should be: ansible_user: armand
   
   # For foundation/production
   cat ansible/inventories/prod/hosts-foundation.yml | grep ansible_user
   # Should be: ansible_user: ansible
   ```

**Solutions**:
- Ensure you can SSH manually with your existing user
- Verify `ansible_user` in inventory matches the phase (armand for bootstrap, ansible for others)
- Check bootstrap completed successfully before running foundation/production
- Re-run bootstrap if needed: `./scripts/run-ansible.sh prod <hostname> bootstrap`

### Password authentication still works after bootstrap

**Symptoms**: Can still SSH with password after bootstrap

**Diagnosis**:
1. **Check SSH service status**:
   ```bash
   ssh armand@192.168.1.40 "sudo systemctl status ssh"
   ```

2. **Verify SSH configuration**:
   ```bash
   ssh armand@192.168.1.40 "sudo grep PasswordAuthentication /etc/ssh/sshd_config.d/*"
   # Should show: PasswordAuthentication no
   ```

3. **Check bootstrap completed**:
   - Review bootstrap playbook output for errors

**Solutions**:
- Restart SSH service: `ssh armand@192.168.1.40 "sudo systemctl restart ssh"`
- Verify bootstrap playbook completed successfully
- Check SSH config file exists: `/etc/ssh/sshd_config.d/10-intergalactic-bootstrap.conf`

### Tailscale not connecting

**Symptoms**: Tailscale status shows "not connected" or connection fails

**Diagnosis**:
1. **Check auth key configuration**:
   ```bash
   grep tailscale_authkey ansible/inventories/prod/group_vars/all_secrets.yml
   # Should not be empty or placeholder
   ```

2. **Check Tailscale service**:
   ```bash
   ssh ansible@<host> "sudo systemctl status tailscaled"
   ```

3. **Check Tailscale logs**:
   ```bash
   ssh ansible@<host> "sudo journalctl -u tailscaled -n 50"
   ```

4. **Verify firewall allows Tailscale**:
   ```bash
   ssh ansible@<host> "sudo nft list ruleset | grep 41641"
   ```

**Solutions**:
- Verify `tailscale_authkey` is set and valid (not expired)
- Check firewall allows UDP port 41641
- Verify Tailscale service is running: `sudo systemctl start tailscaled`
- Check for network connectivity issues

### Can't SSH into Pi after bootstrap

**Symptoms**: Locked out after running bootstrap

**Diagnosis**:
1. **Check SSH keys are configured**:
   ```bash
   # On your local machine
   cat ansible/inventories/prod/group_vars/all_secrets.yml | grep -A 10 "automation_authorized_keys"
   ```

2. **Verify key file exists**:
   ```bash
   ls -la ~/.ssh/intergalactic_ansible
   ```

3. **Test with verbose SSH**:
   ```bash
   ssh -v -i ~/.ssh/intergalactic_ansible ansible@192.168.1.40
   ```

**Solutions**:
- **If you have physical/console access**: Add SSH keys manually:
  ```bash
  # On the Pi (via console)
  sudo mkdir -p /etc/ssh/authorized_keys.d
  echo "your-public-key" | sudo tee /etc/ssh/authorized_keys.d/ansible
  sudo chmod 644 /etc/ssh/authorized_keys.d/ansible
  sudo systemctl reload ssh
  ```
- Verify SSH keys are correct in `all_secrets.yml`
- Check you're using the correct username (`ansible` not `armand` after bootstrap)
- Verify bootstrap playbook completed successfully

### "Host key checking" errors

**Symptoms**: Ansible fails with "Host key verification failed"

**Diagnosis**:
```bash
# Check known_hosts
cat ~/.ssh/known_hosts | grep 192.168.1.40
```

**Solutions**:
- Remove old host key: `ssh-keygen -R 192.168.1.40`
- The bootstrap playbooks automatically fetch and add host keys
- **Security**: Do NOT disable host key checking - it prevents MITM attacks

### Can't find Raspberry Pi on network

**Symptoms**: Cannot reach Pi via network

**Diagnosis**:
1. **Check Pi is powered on**:
   - Verify power LED is on
   - Check network LED activity

2. **Check network connectivity**:
   ```bash
   # Scan network
   nmap -sn 192.168.1.0/24
   
   # Or check router admin page
   ```

3. **Check Pi network configuration**:
   ```bash
   # If you have console access
   ip addr show
   ping 8.8.8.8
   ```

**Solutions**:
- Verify Pi is powered on and connected to network
- Check Ethernet cable or WiFi connection
- Verify Pi and your computer are on the same network
- Check router admin page for connected devices
- Try different network port or cable

### Playbook execution errors

**Symptoms**: Playbook fails with various errors

**Debugging steps**:
1. **Run with verbose output**:
   ```bash
   ./scripts/run-ansible.sh prod <hostname> <phase> -vvv
   ```

2. **Check Ansible logs**:
   - Review playbook output for specific error messages
   - Look for failed tasks and their error messages

3. **Check system logs on target host**:
   ```bash
   ssh ansible@<host> "sudo journalctl -xe"
   ```

4. **Validate playbook syntax**:
   ```bash
   ./scripts/validate-playbooks.sh
   ```

**Common errors**:
- **YAML syntax errors**: Check indentation and quotes
- **Variable not defined**: Check inventory and group_vars
- **Permission denied**: Check sudo access and SSH keys
- **Package installation fails**: Check network connectivity and apt sources

### Role-specific troubleshooting

#### Docker issues
- **Docker not starting**: Check Docker service: `sudo systemctl status docker`
- **Container not running**: Check logs: `docker logs <container-name>`
- **Port conflicts**: Check what's using the port: `sudo netstat -tuln | grep :8000`

#### Firewall issues
- **Cannot access services**: Check firewall rules: `sudo nft list ruleset`
- **Port not open**: Verify port is in `firewall_allow_tcp_ports`
- **Tailscale services not accessible**: Check `internal_dns_enabled` or `edge_ingress_enabled` are set

#### DNS issues
- **DNS not resolving**: Check CoreDNS is running: `docker ps | grep coredns`
- **Wrong IP**: Check Tailscale IP: `tailscale ip -4`
- **Zone file errors**: Check zone file: `sudo cat /opt/coredns/db.exnada.com`

#### Traefik issues
- **SSL certificate not issued**: Check ACME logs: `docker logs traefik | grep -i acme`
- **Backend not reachable**: Check backend service is running and accessible
- **HTTP not redirecting**: Check Traefik configuration: `sudo cat /opt/traefik/traefik.yml`

#### Samba issues
- **Cannot access Samba share**: Check Samba service: `sudo systemctl status smbd`
- **Authentication fails**: Verify password is set: `sudo pdbedit -L | grep armand`
- **Configuration changes not applied**: Use update script: `./scripts/update-samba.sh prod <hostname>`
- **Check Samba configuration**: `sudo testparm -s`

### Debugging playbook execution

**Enable verbose output**:
```bash
# Add -v, -vv, or -vvv for increasing verbosity
ansible-playbook -vvv -i inventories/prod/hosts-production.yml playbooks/rigel-production.yml
```

**Check specific task**:
```bash
# Run playbook with specific tag
ansible-playbook --tags "security" -i inventories/prod/hosts-production.yml playbooks/rigel-production.yml
```

**Test connectivity**:
```bash
# Test SSH connectivity
ansible all -i inventories/prod/hosts-production.yml -m ping

# Test with specific user
ansible all -i inventories/prod/hosts-production.yml -m ping -u ansible
```

### Log analysis

**System logs**:
```bash
# Recent system logs
ssh ansible@<host> "sudo journalctl -n 100"

# Service-specific logs
ssh ansible@<host> "sudo journalctl -u docker -n 50"
ssh ansible@<host> "sudo journalctl -u tailscaled -n 50"
```

**Application logs**:
```bash
# Docker container logs
ssh ansible@<host> "docker logs <container-name>"

# Application logs
ssh ansible@<host> "sudo tail -f /var/log/apps/*.log"
```

### Network troubleshooting

**Check connectivity**:
```bash
# Ping test
ping <host-ip>

# Port test
nc -zv <host-ip> 22

# Tailscale connectivity
tailscale ping <hostname>
```

**Check DNS resolution**:
```bash
# Test DNS
dig @127.0.0.1 mpnas.exnada.com
nslookup mpnas.exnada.com
```

**Check firewall rules**:
```bash
# List all rules
sudo nft list ruleset

# Check specific port
sudo nft list ruleset | grep :8000
```

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

# Update Samba configuration (without running full playbook)
./scripts/update-samba.sh prod <hostname>

# SSH into Pi with ansible user (local IP)
ssh -i ~/.ssh/intergalactic_ansible ansible@<pi-ip-address>

# SSH into Pi via Tailscale (after foundation)
ssh -i ~/.ssh/intergalactic_ansible ansible@<hostname>.tailnet-name.ts.net
```

### File Locations

- **Secrets**: `ansible/inventories/prod/group_vars/all_secrets.yml` (SSH keys, Tailscale key, Hostinger API token)
- **Bootstrap inventory**: `ansible/inventories/prod/hosts-bootstrap.yml` (Phase 1: local IP, armand user)
- **Foundation inventory**: `ansible/inventories/prod/hosts-foundation.yml` (Phase 2: local IP, ansible user)
- **Production inventory**: `ansible/inventories/prod/hosts-production.yml` (Phase 3: Tailscale hostname, ansible user)
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

### Partition Layout for 128GB Drives

This project uses a standard 3-partition layout optimized for Raspberry Pi systems:

**Partition Layout:**
- **Partition 1**: 1GB (FAT32, `/boot`) - Boot partition for kernel and initramfs
- **Partition 2**: 32GB (ext4, `/`) - Root filesystem with OS and system files
- **Partition 3**: ~95GB (ext4, `/home`) - Data partition for user data and Docker storage

**What Goes Where:**
- `/boot`: Kernel, initramfs, boot configuration (unencrypted, required for boot)
- `/`: Operating system, system packages, SSH keys in `/etc/ssh/authorized_keys.d/` (unencrypted)
- `/home`: User home directories, Docker data (`/home/deploy/docker`), service data (`/home/deploy/srv`), application logs (`/home/deploy/logs`) (unencrypted)

**Rationale:**
- **1GB boot**: Standard size for Raspberry Pi, sufficient for kernel and boot files
- **32GB root**: Provides comfortable headroom for:
  - Debian base system (~2-3GB)
  - System packages and updates (~5-10GB)
  - Docker engine and base images (~5-10GB)
  - Logs, temp files, and buffer (~5GB)
- **~95GB data**: All user data, Docker images/containers, service data, and logs

**Note**: Internal partitions are **not encrypted**. LUKS/cryptsetup is installed for mounting **external** encrypted devices (USB drives, network storage).

#### Setting Up Partitions

**Before running bootstrap**, partition your drive:

```bash
# Identify your drive (replace /dev/sdX with your actual device)
lsblk
sudo fdisk -l

# Partition using parted (recommended)
sudo parted /dev/sdX

# In parted:
(parted) mklabel gpt
(parted) mkpart primary fat32 1MiB 1025MiB
(parted) set 1 esp on
(parted) mkpart primary ext4 1025MiB 33793MiB
(parted) mkpart primary ext4 33793MiB 100%

# Format partitions
sudo mkfs.vfat -F 32 /dev/sdX1
sudo mkfs.ext4 /dev/sdX2
sudo mkfs.ext4 /dev/sdX3

# Mount and install OS to partitions 1 and 2
# (Use Raspberry Pi Imager or manual installation)
```

**Or use `fdisk`:**

```bash
sudo fdisk /dev/sdX
# Type 'g' to create GPT partition table
# Type 'n' to create partition 1: start=2048, end=2099200 (1GB)
# Type 't' to set type: 1 (EFI System)
# Type 'n' to create partition 2: start=2099200, end=69206016 (32GB)
# Type 'n' to create partition 3: start=69206016, end=<default> (rest of disk)
# Type 'w' to write and exit

# Format partitions
sudo mkfs.vfat -F 32 /dev/sdX1
sudo mkfs.ext4 /dev/sdX2
sudo mkfs.ext4 /dev/sdX3
```

**After installation**, ensure `/home` is mounted from partition 3 in `/etc/fstab`:

```bash
# Add to /etc/fstab (replace /dev/sdX3 with your actual partition)
UUID=<partition3-uuid> /home ext4 defaults 0 2

# Find UUID: sudo blkid /dev/sdX3
```

### LUKS/Cryptsetup for External Devices

The `luks` role installs `cryptsetup` which enables mounting **external** LUKS-encrypted devices (USB drives, network storage). Internal partitions are **not encrypted**.

**To mount an external encrypted device:**

```bash
# Check if device is encrypted
sudo cryptsetup isLuks /dev/sdX1

# Open encrypted device
sudo cryptsetup open /dev/sdX1 my-encrypted-drive

# Mount the decrypted device
sudo mount /dev/mapper/my-encrypted-drive /mnt

# When done, unmount and close
sudo umount /mnt
sudo cryptsetup close my-encrypted-drive
```

### Docker Data-Root and Directory Structure

The production phase configures Docker to store all data in `/home/deploy/docker` (on the data partition) instead of the default `/var/lib/docker` (on root partition). This keeps Docker data separate from the OS and makes it easier to manage.

**Directory Structure:**

- `/home/deploy/docker/` - Docker data-root (images, containers, volumes, networks)
- `/home/deploy/srv/` - Service data (bind mounted to `/srv`)
- `/home/deploy/logs/apps/` - Application logs (bind mounted to `/var/log/apps`)

**Bind Mounts:**

- `/srv` → `/home/deploy/srv` (service data accessible at standard location)
- `/var/log/apps` → `/home/deploy/logs/apps` (application logs at standard location)

All directories are owned by the `deploy` user and are on the data partition, keeping the root partition clean and organized.

---

## Verification and Testing

This project uses a comprehensive three-phase testing strategy to ensure playbooks and roles work correctly:

### Phase 1: Linting and Syntax Checks (Immediate)

**Tools**: `ansible-lint`, `yamllint`, `ansible-playbook --syntax-check`

**Purpose**: Catch errors before they reach production

**Installation**: **No installation required!** All tools run in Docker containers.

**Usage**:
```bash
# Run all linting checks (containerized)
./scripts/run-linting.sh

# Run syntax validation (containerized)
./scripts/validate-playbooks.sh

# Run specific linter
./scripts/run-linting.sh ansible-lint
./scripts/run-linting.sh yamllint
```

**Requirements**: Only Docker (no Python, pip, or virtual environments needed)

**What it checks**:
- YAML syntax errors
- Ansible best practices
- Deprecated modules
- Security issues
- Playbook syntax

### Phase 2: Molecule Role Testing (Short-term)

**Tools**: `molecule`, `molecule-plugins[docker]`

**Purpose**: Test roles in isolated environments

**Installation**: **No installation required!** All tools run in Docker containers.

**Usage**:
```bash
# Test all roles with Molecule (containerized)
./scripts/run-molecule-tests.sh

# Test specific role
./scripts/run-molecule-tests.sh docker_deploy
```

**Requirements**: Docker (with Docker socket accessible for Docker-in-Docker)

**Roles with Molecule tests**:
- `docker_deploy` - Docker deployment user setup
- `internal_dns` - CoreDNS configuration
- `edge_ingress` - Traefik ingress routing
- `firewall_nftables` - Firewall configuration

**What it tests**:
- Role idempotency (running twice produces no changes)
- Role convergence (role applies successfully)
- Role verification (expected state is achieved)

### Phase 3: Testinfra Production Verification (Long-term)

**Tools**: `testinfra`, `pytest`

**Purpose**: Verify actual server state after deployment

**Installation**: **No installation required!** All tools run in Docker containers.

**Usage**:
```bash
# Test specific host (containerized, requires SSH keys)
docker run --rm -it \
  -v $(pwd):/repo \
  -v $HOME/.ssh:/root/.ssh:ro \
  intergalactic-ansible-testing:latest \
  pytest tests/testinfra/ \
    --hosts=ansible://rigel \
    --ansible-inventory=ansible/inventories/prod/hosts.yml \
    -v
```

**Requirements**: Docker and SSH keys configured

**Test files**:
- `tests/testinfra/test_common.py` - Common system configuration
- `tests/testinfra/test_docker.py` - Docker installation and configuration
- `tests/testinfra/test_firewall.py` - Firewall configuration
- `tests/testinfra/test_tailscale.py` - Tailscale connectivity

**What it tests**:
- Services are running and enabled
- Packages are installed
- Configuration files exist and are correct
- Users and groups are configured
- Network interfaces are up

### Running All Tests

Run all automated tests (containerized, no installation needed):

```bash
# Just run - containers are built automatically
./scripts/run-all-tests.sh
```

Skip specific phases:
```bash
./scripts/run-all-tests.sh --skip-molecule --skip-testinfra
```

**Note**: All tests run in Docker containers - no host installation required!

### Pre-commit Hooks (Optional)

The project includes pre-commit hooks for automatic linting (optional - scripts work without them):

```bash
# Install pre-commit (optional - can use containerized scripts instead)
pip install pre-commit

# Install hooks
pre-commit install

# Run hooks manually
pre-commit run --all-files
```

**Hooks configured**:
- `ansible-lint` - Lints Ansible files
- `yamllint` - Lints YAML files
- `ansible-playbook --syntax-check` - Validates playbook syntax

**Note**: Pre-commit hooks require local installation. For containerized approach, just use the scripts directly.

### Continuous Integration

Add to your CI/CD pipeline (no setup required - containers are built automatically):

```yaml
# Example GitHub Actions workflow
- name: Run linting
  run: ./scripts/run-linting.sh

- name: Validate playbooks
  run: ./scripts/validate-playbooks.sh

- name: Run Molecule tests
  run: ./scripts/run-molecule-tests.sh
```

**Note**: CI/CD systems typically have Docker pre-installed, so no additional setup is needed!

### Testing Workflow

**Before committing**:
1. Run `./scripts/run-linting.sh` (containerized)
2. Run `./scripts/validate-playbooks.sh` (containerized)
3. Run `ansible-playbook --check` on changed playbooks (using existing Docker setup)

**Before merging**:
1. All linting passes
2. All syntax checks pass
3. Molecule tests pass (for changed roles, containerized)
4. Manual testing on staging (if available)

**In production**:
1. Run Testinfra tests regularly (containerized)
2. Monitor for configuration drift
3. Verify idempotency periodically

### Documentation

- **`TESTING_STRATEGY.md`** - Detailed testing strategy and recommendations
- **`TESTING_INSTALLATION.md`** - Containerized installation guide (no host installation needed!)
- **`tests/testinfra/README.md`** - Testinfra test documentation
- **`ansible/requirements-dev.txt`** - Development dependencies (for reference, not required for containerized approach)

### Role Descriptions

- **docker_deploy**: Sets up a `deploy` user for Docker container deployment. Creates user with SSH access (using same keys as `armand`), configures directory structure (`/home/deploy/docker`, `/home/deploy/srv`, `/home/deploy/logs`), sets up bind mounts, installs git, sets up passwordless sudo, and optionally configures Docker daemon DNS and environment variables. Enable with `enable_docker_deploy: true` in host_vars.
- **LUKS**: Installs `cryptsetup` for mounting external LUKS-encrypted devices (USB drives, network storage). Internal partitions are not encrypted.

### Verify Inventory Users

Ensure all hosts use correct users in inventory files:

```bash
./scripts/verify-inventory-users.sh
```

This verifies:
- Bootstrap inventory: All hosts use `ansible_user: armand`
- Production inventory: All hosts use `ansible_user: ansible`
- All hosts are present in both inventories

### Update Samba Configuration

If you need to update Samba configuration without running the full playbook:

```bash
./scripts/update-samba.sh prod <hostname>
```

**What this does:**
- Deploys updated Samba configuration from template (`ansible/roles/samba/templates/smb.conf.j2`)
- Validates configuration syntax using `testparm`
- Restarts Samba services (smbd, nmbd)

**When to use:**
- After modifying the Samba template (`ansible/roles/samba/templates/smb.conf.j2`)
- After changing Samba-related variables in inventory
- When Samba configuration needs to be refreshed without full deployment
- Quick troubleshooting of Samba configuration issues

**Requirements:**
- Host must be accessible via Tailscale (uses `hosts-production.yml`)
- Host must have Samba installed (via `samba` role)
- Host must have `enable_samba: true` in host_vars

**Example:**
```bash
# Update Samba config on rigel
./scripts/update-samba.sh prod rigel

# Update Samba config on vega
./scripts/update-samba.sh prod vega
```

**Note**: This script only updates the Samba configuration file and restarts services. It does not:
- Install Samba (use full playbook for that)
- Add/remove Samba users (use full playbook for that)
- Change Samba passwords (use full playbook for that)

---

## Re-configuring Existing Hosts

If you have hosts that were previously configured with the old single-phase approach, you should re-configure them using the new three-phase structure. This ensures all hosts follow the same architecture and are in a known good state.

**Recommended Approach:**

1. **If the host already has Tailscale:**
   - Get Tailscale hostname: `tailscale status | grep <hostname>`
   - Update `hosts-production.yml` with Tailscale hostname
   - Run production phase: `./scripts/run-ansible.sh prod <hostname> production`

2. **If the host doesn't have Tailscale yet:**
   - Ensure host is accessible via local IP
   - Update `hosts-foundation.yml` with local IP and `ansible_user: ansible`
   - Run foundation phase: `./scripts/run-ansible.sh prod <hostname> foundation`
   - Update `hosts-production.yml` with Tailscale hostname (from foundation output)
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
   - Update `ansible/inventories/prod/hosts-production.yml` with Tailscale hostname (from foundation output)
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