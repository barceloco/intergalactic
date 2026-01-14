# Certificate Issuer Diagnostic and Execution Scripts

These scripts help diagnose and manually execute certificate issuance when Ansible async tasks timeout or fail.

## Scripts

### 1. `diagnose-cert-issuer.sh`
Comprehensive diagnostic script that checks all aspects of the certificate issuer setup.

**Usage:**
```bash
# Copy to rigel and run
scp scripts/diagnose-cert-issuer.sh rigel:/tmp/
ssh rigel "chmod +x /tmp/diagnose-cert-issuer.sh && sudo /tmp/diagnose-cert-issuer.sh"
```

**What it checks:**
- Docker installation and status
- Lego container image availability
- Directory structure and permissions
- Configuration files
- Script executability
- Existing certificates
- Systemd timer status
- Network connectivity
- GoDaddy API credentials

### 2. `run-cert-issuance.sh`
Manual certificate issuance script. Runs directly on rigel.

**Usage:**
```bash
# Copy to rigel and run
scp scripts/run-cert-issuance.sh rigel:/tmp/
ssh rigel "chmod +x /tmp/run-cert-issuance.sh && sudo /tmp/run-cert-issuance.sh [staging|production]"
```

**Options:**
- `staging` (default): Use Let's Encrypt staging environment (test certificates)
- `production`: Use Let's Encrypt production environment (real certificates)

**What it does:**
1. Validates environment and credentials
2. Checks if certificate exists (renewal vs. issuance)
3. Runs lego in Docker container
4. Deploys certificates to Traefik
5. Verifies certificates are in place

### 3. `run-cert-issuance-docker.sh`
Wrapper script that copies and executes the issuance script via SSH.

**Usage:**
```bash
./scripts/run-cert-issuance-docker.sh [staging|production]
```

## Quick Start

### Step 1: Diagnose
```bash
# Copy diagnostic script
scp scripts/diagnose-cert-issuer.sh rigel:/tmp/
ssh rigel "chmod +x /tmp/diagnose-cert-issuer.sh && sudo /tmp/diagnose-cert-issuer.sh"
```

### Step 2: Fix any issues found
Review the diagnostic output and fix any problems (missing files, permissions, etc.)

### Step 3: Run certificate issuance
```bash
# For staging (test certificates)
scp scripts/run-cert-issuance.sh rigel:/tmp/
ssh rigel "chmod +x /tmp/run-cert-issuance.sh && sudo /tmp/run-cert-issuance.sh staging"

# For production (real certificates)
ssh rigel "sudo /tmp/run-cert-issuance.sh production"
```

## Troubleshooting

### Certificate Issuance Fails

1. **Check DNS propagation:**
   ```bash
   dig _acme-challenge.exnada.com TXT +short
   ```

2. **Check GoDaddy API credentials:**
   ```bash
   sudo cat /etc/lego/godaddy_api_key
   sudo cat /etc/lego/godaddy_api_secret
   ```

3. **Check lego logs:**
   ```bash
   sudo journalctl -u lego-renew.service -n 100
   ```

4. **Run preflight checks:**
   ```bash
   sudo /etc/lego/lego-preflight.sh
   ```

### Async Task Timeout

If Ansible async tasks timeout (common with DNS propagation), use the manual scripts:

1. Run diagnostic to verify setup
2. Run manual issuance script
3. Re-run Ansible playbook (it will skip issuance if certificates exist)

### Certificate Not Deployed

If certificate is issued but not deployed to Traefik:

```bash
# Manually deploy
sudo /etc/lego/deploy-internal-certs.sh

# Verify certificates
ls -la /opt/traefik/certs/

# Restart Traefik
docker restart traefik
```

## Notes

- Certificate issuance can take 5-10 minutes due to DNS propagation
- Staging certificates are for testing only (browsers will show warnings)
- Production certificates are trusted by browsers
- The scripts use Docker containers (no local installation needed)
- All scripts require root/sudo access
