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
**Connection**: **Tailscale network ONLY** (rigel.tailb821ac.ts.net)  
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
#      ansible_host: rigel.tailb821ac.ts.net  # Or just "rigel" with MagicDNS
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
ssh -i ~/.ssh/intergalactic_ansible ansible@<hostname>.tailb821ac.ts.net
```

### Running Only Specific Parts

Ansible is **idempotent by default** - it only runs tasks that need to run. However, you can also target specific roles or resume from failures:

```bash
# Run only monitoring role (skip everything else)
./scripts/run-ansible.sh prod rigel production --tags monitoring

# Run only services (DNS, ingress, docker_deploy)
./scripts/run-ansible.sh prod rigel production --tags services

# Run only security roles
./scripts/run-ansible.sh prod rigel production --tags security

# Skip monitoring (run everything except monitoring)
./scripts/run-ansible.sh prod rigel production --skip-tags monitoring

# Resume from a failed task
./scripts/run-ansible.sh prod rigel production --start-at-task "Install ctop"

# Dry-run (check mode) - see what would change
./scripts/run-ansible.sh prod rigel production --check

# Verbose output to see what's being skipped
./scripts/run-ansible.sh prod rigel production -v
```

**Available tags:**
- `services` - docker_deploy, internal_dns, edge_ingress
- `monitoring` - monitoring_docker
- `security` - luks, firewall, fail2ban, ssh_hardening
- `base` - common, updates
- `network` - tailscale
- `infrastructure` - docker_host

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

## Lessons Learned

This section documents critical issues, solutions, and insights discovered through extensive troubleshooting and deployment. These lessons will save significant time in future deployments and troubleshooting.

### DNS Provider Limitations: Hostinger vs GoDaddy

**Issue**: Traefik's built-in ACME resolver failed to obtain Let's Encrypt certificates using Hostinger DNS API.

**Root Cause**: Hostinger's API keys (obtained from hPanel) do **not** provide write access to DNS records. They only have read permissions, which is insufficient for ACME DNS-01 challenges that require creating and deleting `_acme-challenge` TXT records.

**Solution**: Migrated DNS management to GoDaddy, which provides full DNS API access with write permissions.

**Key Learnings**:
- **Always verify API permissions** before choosing a DNS provider for ACME
- Hostinger API keys are read-only for DNS operations
- GoDaddy API keys provide full DNS management capabilities
- Traefik's ACME resolver requires DNS provider write access for DNS-01 challenges

**Migration Notes**:
- GoDaddy API uses `PUT` for creating new records (not `PATCH`)
- GoDaddy requires domain verification before API access
- API keys must be created with explicit DNS management permissions

### CoreDNS Failthrough/Forwarding for External Domains

**Issue**: Internal hosts (e.g., `mpnas.exnada.com`, `aispector.exnada.com`) resolved correctly, but external subdomains like `www.exnada.com` returned NXDOMAIN or failed to resolve.

**Root Cause**: CoreDNS was configured to serve the `exnada.com` zone authoritatively, but only had A records for private hosts. Queries for unknown subdomains (like `www.exnada.com`) were not being forwarded to upstream DNS servers.

**Solution**: Implemented CoreDNS forwarding using the `forward` plugin within the zone block. The configuration now:
1. Serves specific private hosts authoritatively using the `template` plugin
2. Forwards all other queries (including `www.exnada.com`) upstream using `forward . 8.8.8.8 8.8.4.4`

**Key Configuration**:
```corefile
exnada.com:53 {
    # Serve private hosts authoritatively
    template IN A mpnas.exnada.com {
        answer "mpnas.exnada.com 3600 IN A 100.72.27.93"
    }
    # ... more templates ...
    
    # Forward all other queries upstream
    forward . 8.8.8.8 8.8.4.4
}
```

**Key Learnings**:
- CoreDNS can serve a zone authoritatively while forwarding unknown queries
- The `forward` directive must be inside the zone block to work correctly
- Use `forward .` (with dot) to forward all non-matching queries
- This enables split-horizon DNS: internal hosts resolve to Tailscale IPs, external hosts resolve via public DNS

### DNS Resolution for Reverse-Proxy Routing

**Issue**: HTTP requests to `mpnas.exnada.com` were going directly to mpnas (bypassing Traefik), resulting in no HTTPS redirect and direct HTTP access.

**Root Cause**: `mpnas.exnada.com` was resolving to mpnas's Tailscale IP (`100.120.170.43`), so browsers connected directly to mpnas instead of rigel (where Traefik runs).

**Solution**: Modified DNS resolution so reverse-proxied hosts resolve to rigel's IP (where Traefik runs):
- `mpnas.exnada.com` → `100.72.27.93` (rigel/Traefik) - for HTTP/HTTPS
- `aispector.exnada.com` → `100.72.27.93` (rigel/Traefik) - for HTTP/HTTPS
- `dev.exnada.com` → `100.72.27.93` (rigel/Traefik) - for HTTP/HTTPS

**Implementation**: Added logic in `internal_dns` role to override DNS IPs for hosts that are configured in `edge_ingress_routes`, forcing them to resolve to the Traefik host (rigel).

**Key Learnings**:
- **DNS resolution determines routing**: If a hostname resolves to a backend server, requests bypass the reverse proxy
- Reverse-proxied hosts must resolve to the proxy server's IP, not the backend's IP
- SMB/CIFS access can still work using Tailscale FQDNs directly: `mpnas.tailb821ac.ts.net`
- This is a fundamental principle: DNS resolution and reverse proxy routing are tightly coupled

**For SMB Access**:
- Use Tailscale FQDNs directly: `smb://mpnas.tailb821ac.ts.net/armand`
- Or create separate DNS names: `smb-mpnas.exnada.com` → mpnas's IP

### HTTP→HTTPS Redirect: Entrypoint-Level vs Router-Level

**Issue**: HTTP requests to `mpnas.exnada.com` were not redirecting to HTTPS, even though Traefik was configured with redirect middleware.

**Root Cause**: Router-level redirect middleware (`redirectScheme`) was not working reliably. The entrypoint-level redirect (configured in Traefik's static configuration) was removed, leaving no redirect mechanism.

**Solution**: Restored entrypoint-level HTTP→HTTPS redirect in Traefik's static configuration (`traefik.yml`):

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
```

**Key Learnings**:
- **Entrypoint-level redirects are more reliable** than router-level redirects for global HTTP→HTTPS
- Entrypoint redirects happen before routing, ensuring all HTTP traffic is redirected
- Router-level redirects require matching routers, which can fail if configuration is incomplete
- Use entrypoint redirects for global policies, router redirects for specific routes

**Best Practice**: Always configure entrypoint-level redirects for production HTTPS deployments.

### Content Security Policy (CSP) Headers Blocking JavaScript

**Issue**: `mpnas.exnada.com` (Synology NAS) displayed HTML correctly but JavaScript failed to load, resulting in a blank white screen.

**Root Cause**: The Synology backend was sending a restrictive `Content-Security-Policy` header that blocked JavaScript execution. The CSP policy was designed for direct access, not for reverse proxy scenarios.

**Solution**: Created a Traefik middleware (`remove-csp`) that removes the `Content-Security-Policy` header:

```yaml
remove-csp:
  headers:
    customResponseHeaders:
      Content-Security-Policy: ""
```

Applied this middleware to the `mpnas.exnada.com` route before other security headers.

**Key Learnings**:
- **CSP headers can break reverse-proxied applications** that weren't designed for proxy scenarios
- Backend services may send headers that conflict with reverse proxy security policies
- Removing problematic headers is sometimes necessary for compatibility
- Always test JavaScript functionality, not just HTML rendering

**Implementation Details**:
- Middleware order matters: `remove-csp` must be applied before `security-headers`
- Only remove CSP for specific routes that need it (not globally)
- Consider adding custom CSP policies if needed, rather than removing entirely

### X-Content-Type-Options: nosniff Blocking CSS and JavaScript

**Issue**: CSS and JavaScript files on `mpnas.exnada.com` failed to load with errors:
- `Did not parse stylesheet at '...' because non CSS MIME types are not allowed in strict mode`
- `Refused to execute ... as script because "X-Content-Type-Options: nosniff" was given and its Content-Type is not a script MIME type`

**Root Cause**: 
1. The Synology backend sends `Content-Type: text/html` for CSS and JavaScript files (incorrect MIME types)
2. Our security headers include `X-Content-Type-Options: nosniff` (correct security practice)
3. Browsers enforce strict MIME type checking when `nosniff` is present, refusing to parse CSS/JS with incorrect Content-Type

**Solution**: Created a separate security headers middleware (`security-headers-no-nosniff`) that includes all security headers except `X-Content-Type-Options: nosniff`. This middleware is applied to routes with `force_html_content_type: true` instead of the standard `security-headers` middleware:

```yaml
security-headers-no-nosniff:
  headers:
    sslRedirect: true
    forceSTSHeader: true
    stsIncludeSubdomains: true
    stsPreload: true
    stsSeconds: 31536000
    customFrameOptionsValue: "SAMEORIGIN"
    customRequestHeaders:
      X-Forwarded-Proto: "https"
    customResponseHeaders:
      # Note: X-Content-Type-Options: nosniff is intentionally omitted
      X-Frame-Options: "SAMEORIGIN"
      X-XSS-Protection: "1; mode=block"
      Referrer-Policy: "strict-origin-when-cross-origin"
      Permissions-Policy: "geolocation=(), microphone=(), camera=()"
```

**Why a separate middleware instead of removing the header?**
- Traefik doesn't allow removing headers that were set by earlier middlewares
- Creating a separate middleware without `nosniff` is the only way to exclude it
- This approach maintains all other security headers while allowing MIME type sniffing

Applied this middleware to the `mpnas.exnada.com` route (via `force_html_content_type: true` flag) instead of the standard `security-headers` middleware.

**Key Learnings**:
- **X-Content-Type-Options: nosniff is a security feature** that prevents MIME type sniffing attacks
- **Backend services may send incorrect Content-Type headers** (e.g., `text/html` for CSS/JS)
- **Browsers strictly enforce MIME types** when `nosniff` is present
- **Removing nosniff is a security trade-off** but necessary for compatibility with misconfigured backends
- **Only remove nosniff for specific routes** that need it, not globally

**Security Considerations**:
- Removing `nosniff` allows browsers to perform MIME type sniffing, which can be a security risk
- However, for internal services behind a reverse proxy, this risk is acceptable
- The alternative (fixing backend Content-Type headers) is not always possible with third-party services
- Consider this a compatibility workaround, not a security best practice

**Implementation Details**:
- Created separate middleware `security-headers-no-nosniff` (all headers except `nosniff`)
- Applied to routes with `force_html_content_type: true` flag instead of standard `security-headers`
- Middleware order: `security-headers-no-nosniff` → `retry` → `remove-csp`
- **Important**: Removed `content-type-html` middleware - Synology sends correct Content-Type headers (`text/css` for CSS, `application/javascript` for JS)
- The `content-type-html` middleware was forcing `text/html` on ALL responses, breaking CSS/JS files
- Other routes still use standard `security-headers` with `nosniff` protection
- **Why separate middleware?** Traefik doesn't allow removing headers that were set by earlier middlewares, so we must use a different middleware that never sets `nosniff` in the first place

**What Synology Should Send (and Does Send)**:
- CSS files: `Content-Type: text/css` ✅
- JavaScript files: `Content-Type: application/javascript` ✅
- HTML files: `Content-Type: text/html; charset=utf-8` ✅

**The Real Problem**:
- Synology sends correct Content-Type headers when accessed directly
- Our `content-type-html` middleware was overriding ALL responses with `text/html`
- Combined with `nosniff`, this caused browsers to reject CSS/JS files
- Solution: Remove `content-type-html` middleware and use `security-headers-no-nosniff` to allow MIME type sniffing
- **Why separate middleware?** Traefik doesn't allow removing headers set by earlier middlewares, so we must use a different middleware that never sets `nosniff` in the first place

### Content-Type Headers and File Downloads

**Issue**: Initially, `mpnas.exnada.com` was prompting file downloads instead of displaying HTML pages.

**Root Cause**: The Synology backend was not sending proper `Content-Type: text/html` headers for HTML responses.

**Initial Solution**: Created a middleware to force `Content-Type: text/html` for HTML responses.

**Final Solution**: Discovered the backend was actually sending correct `Content-Type` headers. The real issue was the CSP header blocking JavaScript. Removed the `content-type-html` middleware as it was unnecessary.

**Key Learnings**:
- **Test thoroughly before adding workarounds**: The initial diagnosis was incorrect
- Backend services may send correct headers, but other headers (like CSP) can cause issues
- Browser behavior (download vs display) depends on multiple factors, not just Content-Type
- Always verify the actual HTTP headers being sent before implementing fixes

### X-Forwarded-Host Header for Backend Routing

**Issue**: Backend services (especially Synology) were not receiving the correct Host header, causing routing issues.

**Root Cause**: Traefik was forwarding requests but the backend needed to know the original hostname for proper routing.

**Solution**: Added `X-Forwarded-Host` to the `customRequestHeaders` in the `security-headers` middleware:

```yaml
security-headers:
  headers:
    customRequestHeaders:
      X-Forwarded-Proto: "https"
      X-Forwarded-Host: "{{ route.host }}"  # Added this
```

**Key Learnings**:
- Backend services often use the Host header for routing decisions
- Reverse proxies must forward the original hostname via `X-Forwarded-Host`
- Some services require both `X-Forwarded-Proto` and `X-Forwarded-Host` for proper HTTPS handling
- Always include standard proxy headers: `X-Forwarded-Proto`, `X-Forwarded-Host`, `X-Forwarded-For`

### CoreDNS Health Endpoints and Zone Parsing

**Issue**: CoreDNS container was restarting with errors: `error inspecting server blocks: zone is not a valid domain name`.

**Root Cause**: Health, ready, prometheus, and reload endpoint blocks were placed outside zone blocks or in incorrect locations, causing CoreDNS configuration parsing errors.

**Solution**: Removed health/ready/prometheus/reload endpoint blocks entirely. These endpoints require separate server blocks which conflict with zone-based configuration.

**Key Learnings**:
- CoreDNS configuration syntax is strict about server block placement
- Health endpoints require dedicated server blocks (e.g., `:8080 { health }`)
- Mixing zone blocks and endpoint blocks can cause parsing errors
- For production, use external monitoring instead of built-in health endpoints
- Docker healthchecks can monitor CoreDNS without built-in endpoints

**Alternative**: If health endpoints are needed, use separate top-level server blocks:
```corefile
.:53 {
    # Main DNS handling
}

:8080 {
    health
}
```

### CoreDNS Template Plugin and Empty IP Fallback

**Issue**: CoreDNS was failing with empty IP addresses for some hosts, causing zone parsing errors.

**Root Cause**: The template plugin was receiving empty strings for IP addresses when a host's Tailscale IP couldn't be detected.

**Solution**: Implemented a ternary fallback in the Corefile template:
```jinja2
{{ (internal_dns_host_ips[host] | default('') | length > 0) | ternary(internal_dns_host_ips[host], tailscale_ip) }}
```

This ensures that if a host's IP is empty or not found, it falls back to the current host's Tailscale IP (rigel).

**Key Learnings**:
- **Always validate and provide fallbacks** for dynamic DNS configurations
- Empty strings in DNS records cause parsing errors
- Template plugins require valid data, so fallback logic is essential
- Test DNS resolution for all configured hosts to catch empty IP issues early

### Docker Volume Mounts: Binary vs Directory

**Issue**: Lego container failed with mount error: `error mounting "/opt/lego/data" to rootfs at "/lego": not a directory`.

**Root Cause**: The `goacme/lego` Docker image has `/lego` as a **binary executable**, not a directory. Docker cannot mount a directory over a file.

**Solution**: Changed the internal container mount point from `/lego` to `/data`:
- Host: `/opt/lego/data` (directory)
- Container: `/data` (mount point)
- Binary: `/lego` (executable, not a mount point)

**Key Learnings**:
- **Always inspect Docker images** before mounting volumes: `docker inspect <image>`
- Executable files and directories cannot be interchanged in mount points
- Use `docker run --rm <image> ls -la /` to see image structure
- Mount points must target directories, not files

**Diagnostic Commands**:
```bash
# Inspect image structure
docker inspect goacme/lego:v4.31.0 | grep -A 10 "Env\|Cmd"

# Check what /lego is
docker run --rm goacme/lego:v4.31.0 ls -la /lego

# Verify mount point is a directory
docker run --rm -v /opt/lego/data:/data goacme/lego:v4.31.0 ls -la /data
```

### GoDaddy DNS API: PUT vs PATCH for Record Creation

**Issue**: Creating DNS records via GoDaddy API failed with HTTP 404 "Not Found" when using `PATCH`.

**Root Cause**: GoDaddy's API requires `PUT` for creating new records for subdomains that don't exist yet. `PATCH` only works for updating existing records.

**Solution**: Implemented a fallback mechanism:
1. Try `PATCH` first (for updates)
2. If `PATCH` returns 404, try `PUT` (for creation)

**Key Learnings**:
- **Different HTTP methods for different operations**: PUT for creation, PATCH for updates
- Always check API documentation for method requirements
- Implement fallback logic when API behavior is inconsistent
- Test both creation and update scenarios

**API Pattern**:
```bash
# Update existing record
PATCH /v1/domains/{domain}/records/{type}/{name}

# Create new record
PUT /v1/domains/{domain}/records/{type}/{name}
```

### Duplicate ACME Challenge Records

**Issue**: ACME certificate issuance failed with `DUPLICATE_RECORD` errors for `_acme-challenge` TXT records.

**Root Cause**: Previous failed ACME attempts left `_acme-challenge` TXT records in DNS. New attempts tried to create duplicate records, causing conflicts.

**Solution**: Created cleanup script (`scripts/cleanup-acme-dns-records.sh`) to delete all `_acme-challenge` records before certificate issuance.

**Key Learnings**:
- **ACME challenges leave records behind** if they fail or are interrupted
- Always clean up ACME challenge records before retrying
- Implement cleanup as part of certificate renewal process
- Monitor DNS for orphaned challenge records

**Prevention**: Consider implementing automatic cleanup in certificate renewal scripts.

### Traefik Router Configuration: Services Required for Redirects

**Issue**: HTTP routers configured with only redirect middleware failed with "the service is missing on the router" error.

**Root Cause**: Traefik requires a service to be defined on every router, even if the router only performs redirects. The redirect middleware doesn't eliminate the service requirement.

**Solution**: Added services to HTTP redirect routers, even though they're only used for redirects.

**Key Learnings**:
- **Traefik routers always need services**, even for redirect-only routes
- Redirect middleware doesn't replace the service requirement
- Use entrypoint-level redirects to avoid this complexity
- If using router-level redirects, always include a service (even if unused)

### Traefik Static Configuration Not Updating

**Issue**: Template file (`traefik.yml.j2`) was correct, but deployed file on host had old content.

**Root Cause**: Ansible template task was not being executed, or file was manually edited and not tracked.

**Solution**: Verified template content, ensured playbook runs template task, and manually updated file to test.

**Key Learnings**:
- **Always verify deployed files match templates** after playbook runs
- Use `ansible-playbook --check` to see what would change
- Manually verify critical configuration files after deployment
- Consider using `validate` parameter in template tasks to catch syntax errors early

**Verification**:
```bash
# Check what Ansible would change
ansible-playbook --check playbooks/rigel-production.yml --tags services

# Verify deployed file
ssh rigel "cat /opt/traefik/traefik.yml"

# Compare with template
diff <(ssh rigel "cat /opt/traefik/traefik.yml") <(ansible localhost -m template -a "src=ansible/roles/edge_ingress/templates/traefik.yml.j2 dest=/tmp/test.yml" --extra-vars="@ansible/inventories/prod/host_vars/rigel.yml")
```

### Multiple CoreDNS Containers Running

**Issue**: DNS resolution was inconsistent, sometimes working and sometimes failing.

**Root Cause**: Multiple CoreDNS containers were running simultaneously, causing port conflicts and inconsistent resolution.

**Solution**: Ensured only one CoreDNS container runs by:
1. Stopping all CoreDNS containers: `docker stop $(docker ps -q --filter name=coredns)`
2. Removing old containers: `docker rm $(docker ps -aq --filter name=coredns)`
3. Starting fresh container via Docker Compose

**Key Learnings**:
- **Always check for duplicate containers** when troubleshooting
- Use `docker ps -a --filter name=<container>` to find all instances
- Docker Compose should manage container lifecycle, but manual cleanup may be needed
- Port conflicts can cause silent failures

**Prevention**: Add container cleanup tasks to Ansible playbooks.

### Traefik ACME DNS Resolution Issues

**Issue**: Traefik's ACME resolver failed with "lookup rigel.exnada.com. on 100.100.100.100:53: no such host" errors.

**Root Cause**: Traefik was trying to use Tailscale DNS (`100.100.100.100`) to verify ACME challenge records, but `rigel.exnada.com` doesn't exist in Tailscale DNS (it's an internal hostname).

**Solution**: Configured Traefik's ACME resolver to use Google DNS servers explicitly:

```yaml
dnsChallenge:
  provider: godaddy
  resolvers:
    - "8.8.8.8:53"
    - "8.8.4.4:53"
```

**Key Learnings**:
- **ACME verification must use public DNS**, not internal DNS
- Tailscale DNS doesn't resolve public domain names
- Always configure explicit DNS resolvers for ACME challenges
- Internal DNS and ACME verification DNS must be separate

### Certificate System Conflict: Traefik ACME vs Lego

**Issue**: Two certificate systems were running in parallel, causing confusion and potential conflicts:
- Traefik's built-in ACME resolver (configured in `traefik.yml.j2`)
- Lego cert_issuer role (deploying certificates to `/opt/traefik/certs/`)

**Root Cause**: Both systems were enabled simultaneously:
- `edge_ingress` role configured Traefik with `certificatesResolvers: letsencrypt` (built-in ACME)
- `cert_issuer` role was enabled and issuing certificates via lego
- Traefik routers used `certResolver: letsencrypt` (not file-based certificates)
- Lego certificates in `/opt/traefik/certs/` were not being used by Traefik

**Investigation**:
- Traefik's ACME was configured but failing (DNS resolution errors in logs)
- Lego certificates existed in `/opt/traefik/certs/` but Traefik wasn't configured to use them
- Actual certificates being served were from Traefik's built-in ACME (working correctly)
- Certificate management was inconsistent and confusing

**Solution**: Standardized on **Traefik's built-in ACME resolver** exclusively:
1. Disabled `cert_issuer` role in `rigel.yml` (`cert_issuer_enabled: false`)
2. Commented out `cert_issuer` role in production playbook
3. Updated configuration comments to reflect Traefik ACME usage
4. Kept Traefik's built-in ACME configuration (simpler, more integrated)

**Why Traefik ACME Over Lego**:
- **Simpler**: Integrated directly into Traefik, no separate container
- **Automatic**: Certificates obtained on-demand when routes are accessed
- **Reliable**: Traefik handles renewal automatically
- **Less complexity**: No need for separate deployment scripts or systemd timers
- **Better integration**: Certificates stored in `acme.json`, managed by Traefik

**When to Use Lego Instead**:
- Need certificates for services other than Traefik
- Require more control over certificate issuance process
- Need to share certificates across multiple reverse proxies
- Prefer file-based certificate management

**Key Learnings**:
- **Choose ONE certificate system**: Don't run multiple certificate management systems in parallel
- **Traefik's built-in ACME is simpler** for Traefik-only deployments
- **Lego provides more control** but adds complexity
- **Verify which system is actually serving certificates**: Check what Traefik is using
- **Update configuration comments** to reflect actual certificate management approach
- **Document certificate management strategy** clearly in host_vars and README

**Configuration Pattern**:
```yaml
# Option A: Traefik's built-in ACME (recommended for Traefik-only)
edge_ingress_enabled: true
edge_ingress_disable_tls: false
cert_issuer_enabled: false  # Disabled - using Traefik ACME

# Option B: Lego (for multi-service or advanced control)
edge_ingress_enabled: true
edge_ingress_disable_tls: false
# Configure Traefik for file-based certificates (not certResolver)
cert_issuer_enabled: true
```

### General Principles and Best Practices

#### 1. DNS Resolution Determines Routing
- Where a hostname resolves determines where requests go
- Reverse-proxied hosts must resolve to the proxy server
- Direct access hosts can resolve to their own IPs

#### 2. Test Incrementally
- Test DNS resolution first: `dig @<dns-server> <hostname>`
- Test HTTP connectivity: `curl -I http://<hostname>`
- Test HTTPS connectivity: `curl -k -I https://<hostname>`
- Test full application functionality (not just initial page load)

#### 3. Verify Actual Behavior, Not Assumptions
- Check actual HTTP headers: `curl -v <url>`
- Verify DNS resolution: `dig <hostname>`
- Inspect container logs: `docker logs <container>`
- Don't assume configuration matches reality

#### 4. Container Image Inspection
- Always inspect Docker images before mounting volumes
- Check file structure: `docker run --rm <image> ls -la /`
- Verify mount points are directories, not files
- Test mount operations before deploying

#### 5. API Permissions Matter
- Verify API keys have required permissions (read vs write)
- Test API operations before integrating
- Implement fallback logic for inconsistent APIs
- Document API limitations and requirements

#### 6. Middleware Order Matters
- Traefik processes middlewares in order
- Security headers should come after content modifications
- Redirect middlewares should be early in the chain
- Test middleware interactions, not just individual middlewares

#### 7. Configuration File Validation
- Always validate configuration syntax before deploying
- Use `--check` mode to preview changes
- Verify deployed files match templates
- Test configuration reloads, not just initial deployment

### Current State and Remaining Work

#### What's Working
- ✅ Three-phase deployment model (Bootstrap → Foundation → Production)
- ✅ Tailscale network connectivity
- ✅ Internal DNS (CoreDNS) with failthrough for external domains
- ✅ Edge ingress (Traefik) with HTTPS and HTTP→HTTPS redirect
- ✅ Certificate issuance (Traefik's built-in ACME with GoDaddy DNS-01)
- ✅ Reverse proxy routing for internal services
- ✅ Security headers and middleware configuration
- ✅ DNS resolution for reverse-proxied hosts
- ✅ HSTS headers with preload flag
- ✅ All production scripts integrated in Ansible playbooks
- ✅ Role execution order optimized for dependencies

#### What Needs Testing
- ⚠️ **Certificate renewal automation**: Traefik's built-in ACME handles renewal automatically, but should verify it works
- ⚠️ **Multi-host routing**: Verify all routes work across different hosts (vega, mpnas, rigel)
- ⚠️ **DNS propagation**: Test DNS changes propagate correctly
- ⚠️ **Failover scenarios**: What happens if rigel (Traefik) goes down?
- ⚠️ **Certificate expiration monitoring**: Add alerts for certificates expiring soon

#### What Needs Consideration

##### 1. HTTP→HTTPS Enforcement
**Current State**: HTTP requests redirect to HTTPS, but HTTP is still accessible.

**Considerations**:
- Should we block HTTP entirely at the firewall level?
- Should we add HSTS headers (already configured, but verify enforcement)?
- Should we configure browsers to only use HTTPS for internal domains?

**Recommendations**:
- Keep HTTP→HTTPS redirect (current approach is correct)
- HSTS headers are already configured (31536000 seconds = 1 year)
- Consider firewall rules to block HTTP on public interfaces (but allow on Tailscale)
- Monitor for any HTTP-only access attempts

##### 2. SMB/CIFS Access via Reverse Proxy
**Current State**: SMB access uses Tailscale FQDNs directly (`mpnas.tailb821ac.ts.net`).

**Considerations**:
- Can SMB be proxied through Traefik? (No - SMB uses port 445, not HTTP/HTTPS)
- Should we create separate DNS names for SMB? (e.g., `smb-mpnas.exnada.com`)
- Should we document SMB access patterns?

**Recommendations**:
- **SMB cannot be proxied**: SMB/CIFS is not HTTP-based, so Traefik cannot proxy it
- Keep current approach: Use Tailscale FQDNs for SMB access
- Document SMB access patterns in README
- Consider creating `smb-*.exnada.com` DNS names if users prefer domain names

##### 3. Certificate Management
**Current State**: Certificates are issued via Traefik's built-in ACME resolver with GoDaddy DNS-01 challenge. Automatic renewal is handled by Traefik.

**Considerations**:
- Should we monitor certificate expiration?
- Should we add certificate expiration alerts?
- Should we verify automatic renewal is working?

**Recommendations**:
- **Current approach (Traefik ACME) is correct**: Simpler, more integrated, automatic renewal
- Add monitoring: Alert on certificate expiration (30 days before expiry)
- Verify renewal: Test certificate renewal before expiration
- Consider wildcard certificates: Traefik can obtain per-domain or wildcard certificates

##### 4. DNS Split-Horizon Complexity
**Current State**: CoreDNS serves internal hosts, forwards external hosts.

**Considerations**:
- Should we serve all `exnada.com` subdomains internally?
- Should we have separate internal/external DNS views?
- How do we handle new subdomains?

**Recommendations**:
- **Current approach is correct**: Internal hosts resolve to Tailscale IPs, external hosts resolve via public DNS
- Document DNS resolution patterns clearly
- Consider DNS views if internal/external split becomes complex
- Monitor for DNS resolution issues

##### 5. High Availability
**Current State**: Single Traefik instance on rigel, single CoreDNS instance on rigel.

**Considerations**:
- What happens if rigel goes down?
- Should we run Traefik on multiple hosts?
- Should we run CoreDNS on multiple hosts?

**Recommendations**:
- **Current approach is acceptable** for small deployments
- Consider Traefik redundancy if uptime is critical
- Consider CoreDNS redundancy if DNS is critical
- Document failover procedures

##### 6. Monitoring and Alerting
**Current State**: Basic monitoring (sysstat, docker stats), no alerting.

**Considerations**:
- Should we add Prometheus/Grafana?
- Should we monitor certificate expiration?
- Should we monitor DNS resolution?
- Should we monitor Traefik routing?

**Recommendations**:
- Add certificate expiration monitoring (critical)
- Add DNS resolution monitoring (important)
- Consider Prometheus/Grafana for comprehensive monitoring
- Document monitoring setup

### Safari Browser HTTPS Warning: "Does Not Support HTTPS"

**Issue**: Safari browser reports that `https://mpnas.exnada.com` "does not support https" and suggests using HTTP instead, despite valid Let's Encrypt certificates and proper HTTPS configuration.

**Root Cause**: Safari detects that HTTP is still accessible (even though it redirects to HTTPS) and may interpret this as the site preferring HTTP over HTTPS. Additionally, Safari may not have cached the HSTS header yet, or there may be mixed content issues.

**Investigation Findings**:
- ✅ HTTPS is working correctly: Valid Let's Encrypt certificate (CN=mpnas.exnada.com, issuer=Let's Encrypt R13)
- ✅ Certificate chain is valid: `Verify return code: 0 (ok)`
- ✅ HTTP→HTTPS redirect is working: `HTTP/1.1 301 Moved Permanently` → `Location: https://mpnas.exnada.com/`
- ✅ HSTS header is being sent: `strict-transport-security: max-age=31536000; includeSubDomains; preload`
- ✅ TLS 1.3 is being used: Modern encryption protocol
- ⚠️ HTTP is still accessible (redirects, but Safari may detect this as "HTTP support")

**Solution**: The configuration is correct. Safari's warning may be due to:
1. **HSTS not yet cached**: Safari needs to see the HSTS header at least once before it remembers HTTPS-only
2. **HTTP accessibility**: Safari detects HTTP is accessible (even with redirect) and may warn
3. **Browser cache**: Safari may have cached an old HTTP-only state

**Immediate Actions Taken**:
1. Verified HSTS header is being sent with `preload` flag
2. Verified HTTP redirects are permanent (301) to HTTPS
3. Verified certificate is valid and trusted
4. Ensured all security headers are properly configured

**Resolution Steps for Users**:
1. **Clear Safari cache and HSTS data**:
   - Safari → Settings → Privacy → Manage Website Data → Remove all data for `mpnas.exnada.com`
   - Or: Safari → Develop → Empty Caches
2. **Visit HTTPS directly**: Navigate to `https://mpnas.exnada.com` (not HTTP)
3. **Wait for HSTS to cache**: After first HTTPS visit, Safari will cache HSTS for 1 year
4. **Verify certificate**: Click the padlock icon → Show Certificate → Verify it's from Let's Encrypt

**Configuration Verification**:
```bash
# Verify HTTPS is working
curl -I https://mpnas.exnada.com

# Verify HSTS header is sent
curl -I https://mpnas.exnada.com | grep -i strict-transport

# Verify certificate is valid
openssl s_client -connect mpnas.exnada.com:443 -servername mpnas.exnada.com < /dev/null | grep "Verify return code"

# Verify HTTP redirects
curl -I http://mpnas.exnada.com | grep -E '(HTTP|Location)'
```

**Key Learnings**:
- **HSTS requires first visit**: Browsers must see HSTS header at least once before enforcing HTTPS-only
- **Safari is strict**: Safari may warn if HTTP is accessible, even with redirects
- **Certificate validity is not enough**: Browsers also check for HSTS and proper redirects
- **Browser cache matters**: Old HTTP-only states may be cached
- **Preload flag helps**: HSTS preload ensures browsers never attempt HTTP connections

**Future Considerations**:
- Consider submitting to HSTS preload list (requires `preload` flag, which we have)
- Monitor for any mixed content issues (HTTP resources on HTTPS pages)
- Consider firewall-level HTTP blocking (but this would break redirects)

**Status**: ✅ Configuration is correct. Safari warning should resolve after:
1. Clearing browser cache/HSTS data
2. Visiting HTTPS directly
3. Allowing HSTS to cache (automatic after first visit)

---

### Future Improvements

1. **Automated Testing**: Add integration tests for DNS resolution, Traefik routing, certificate renewal
2. **Documentation**: Add architecture diagrams, network flow diagrams
3. **Monitoring**: Implement comprehensive monitoring and alerting
4. **High Availability**: Consider redundant Traefik and CoreDNS instances
5. **Security Hardening**: Review and enhance security headers, firewall rules
6. **Performance Optimization**: Optimize DNS caching, Traefik routing performance
7. **HSTS Preload Submission**: Submit domains to HSTS preload list for maximum security

---

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