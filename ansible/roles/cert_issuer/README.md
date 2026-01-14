# cert_issuer Role

Deploys automated Let's Encrypt certificate issuance and renewal using `lego` with GoDaddy DNS-01 challenge, running in a dedicated Docker container. Certificates are automatically deployed to Traefik using file-based TLS configuration.

## What This Role Does

- Installs and configures `lego` in a Docker container (using official `goacme/lego` image)
- Uses Docker named volume for lego state (Docker-managed, no host mount issues)
- Obtains wildcard SSL certificates via Let's Encrypt DNS-01 challenge
- Automatically renews certificates 30 days before expiry
- Deploys certificates to Traefik using atomic file operations
- Runs daily via systemd timer
- Handles both initial certificate issuance and renewal

## Requirements

- Debian distribution (tested on Debian trixie/testing)
- Ansible 2.9+
- Root/sudo access (role uses `become: true`)
- **Docker must be installed** (via `docker_host` role)
- **GoDaddy API key and secret** must be configured in `all_secrets.yml`
- **Traefik must be deployed** (via `edge_ingress` role) with certificate directory configured
- Domain must be managed by GoDaddy DNS

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `cert_issuer_enabled` | `false` | Enable this role (set to `true` in host_vars) |
| `cert_issuer_domain` | `exnada.com` | Base domain for certificate |
| `cert_issuer_wildcard` | `true` | Obtain wildcard certificate (`*.exnada.com` + `exnada.com`) |
| `cert_issuer_email` | `admin@exnada.com` | Email for Let's Encrypt ACME registration |
| `cert_issuer_ca_server` | `staging` | ACME CA server (`staging` or `production`) |
| `cert_issuer_lego_version` | `v4.14.2` | Lego Docker image version (pinned for stability) |
| `cert_issuer_renew_days` | `30` | Days before expiry to renew certificate |
| `cert_issuer_data_dir` | `/opt/lego` | Directory for lego Docker Compose and scripts |
| `cert_issuer_container_name` | `lego` | Docker container name for lego |
| `cert_issuer_config_dir` | `/etc/lego` | Directory for configuration files and secrets |
| `cert_issuer_lego_volume` | `lego_data` | Docker named volume for lego state and certificates (Docker-managed) |
| `cert_issuer_godaddy_propagation_timeout` | `180` | DNS propagation timeout (seconds) |
| `cert_issuer_godaddy_polling_interval` | `2` | DNS polling interval (seconds) |
| `cert_issuer_godaddy_ttl` | `600` | DNS TTL for TXT records (seconds) |

## Dependencies

- **docker_host**: Docker must be installed
- **edge_ingress**: Traefik must be deployed with certificate directory configured

## Usage Examples

### Basic Usage

```yaml
# In host_vars/rigel.yml
cert_issuer_enabled: true
cert_issuer_domain: exnada.com
cert_issuer_wildcard: true
cert_issuer_email: admin@exnada.com
cert_issuer_ca_server: staging  # Use 'production' for real certificates
```

### Production Configuration

```yaml
cert_issuer_enabled: true
cert_issuer_domain: exnada.com
cert_issuer_wildcard: true
cert_issuer_email: admin@exnada.com
cert_issuer_ca_server: production
cert_issuer_renew_days: 30
```

## How It Works

1. **Lego Container**: Runs official `goacme/lego` Docker image on-demand via systemd timer
2. **Certificate Issuance**: Uses DNS-01 challenge with GoDaddy DNS provider
3. **Wildcard Certificates**: Obtains `*.exnada.com` and `exnada.com` in single certificate
4. **Automatic Renewal**: Systemd timer runs daily, renews if certificate expires within 30 days
5. **Certificate Deployment**: After successful renewal, deploys certificates to Traefik via atomic file operations
6. **Service Reload**: Restarts Traefik container to load new certificates

## Certificate Files

Certificates are stored in:
- **Lego state**: Docker named volume `lego_data` (mounted at `/lego` inside container)
- **Deployed to Traefik**: `/opt/traefik/certs/`
- **File names**: `exnada.com.crt` and `exnada.com.key` (or `_.exnada.com.crt` for wildcard)

The lego state is stored in a Docker-managed named volume, which eliminates host filesystem mount issues and follows Docker best practices.

## Systemd Timer

The role creates a systemd timer that:
- Runs daily at 3:17 AM (randomized ±1 hour to avoid thundering herd)
- Executes `lego-renew.sh` script
- Logs to systemd journal
- Persists across reboots

## Scripts

### lego-renew.sh
Main renewal script that:
- Checks if certificate exists (run vs renew)
- Executes lego in Docker container
- Triggers deployment hook on successful renewal
- Handles errors gracefully

### deploy-internal-certs.sh
Deployment hook that:
- Copies certificates to Traefik directory
- Sets proper permissions (cert: 0644, key: 0600)
- Backs up existing certificates
- Atomically deploys new certificates
- Reloads Traefik container
- Restores backup on failure

### lego-preflight.sh
Preflight checks that:
- Verifies Docker is available
- Checks token file exists and is readable
- Validates directories exist
- Checks network connectivity

## Security Considerations

- **Credential Storage**: GoDaddy API key and secret stored in `/etc/lego/godaddy_api_key` and `/etc/lego/godaddy_api_secret` with 0600 permissions
- **Environment Variables**: Scripts read credentials from files and pass them as `GODADDY_API_KEY` and `GODADDY_API_SECRET` environment variables to the lego container
- **Certificate Permissions**: Private key 0600, certificate 0644
- **Container Isolation**: Lego runs in dedicated container with minimal volume mounts
- **Atomic Deployment**: Certificates deployed atomically to prevent partial updates

## Troubleshooting

### Certificate Not Issued

1. **Check preflight**:
   ```bash
   sudo /etc/lego/lego-preflight.sh
   ```

2. **Check lego logs**:
   ```bash
   sudo journalctl -u lego-renew.service -n 50
   ```

3. **Verify GoDaddy credentials**:
   ```bash
   sudo cat /etc/lego/godaddy_api_key
   sudo cat /etc/lego/godaddy_api_secret
   ```

4. **Test manual renewal**:
   ```bash
   sudo /etc/lego/lego-renew.sh
   ```

### Certificate Not Deployed

1. **Check deployment script**:
   ```bash
   sudo /etc/lego/deploy-internal-certs.sh
   ```

2. **Verify certificate files exist**:
   ```bash
   ls -la /var/lib/lego/certificates/
   ls -la /opt/traefik/certs/
   ```

3. **Check Traefik container**:
   ```bash
   docker ps | grep traefik
   docker logs traefik | tail -20
   ```

### Timer Not Running

1. **Check timer status**:
   ```bash
   systemctl status lego-renew.timer
   ```

2. **Check next run time**:
   ```bash
   systemctl list-timers lego-renew.timer
   ```

3. **Manually trigger**:
   ```bash
   sudo systemctl start lego-renew.service
   ```

## Testing

### Staging Test

1. Set `cert_issuer_ca_server: staging` in host_vars
2. Run playbook to deploy role
3. Run preflight checks: `sudo /etc/lego/lego-preflight.sh`
4. Manually trigger renewal: `sudo /etc/lego/lego-renew.sh`
5. Verify certificates: `ls -la /opt/traefik/certs/`
6. Test HTTPS: `curl -k https://aispector.exnada.com/health`

### Production Cutover

1. Set `cert_issuer_ca_server: production` in host_vars
2. Run playbook to update configuration
3. Manually trigger renewal: `sudo /etc/lego/lego-renew.sh`
4. Verify production certificates
5. Monitor first automated renewal (check logs after timer runs)

## Integration with Other Roles

- **docker_host**: Docker must be installed
- **edge_ingress**: Traefik must be deployed with certificate directory (`/opt/traefik/certs/`)

## Notes

- **Lego uses official Docker image**: `goacme/lego:v4.14.2` (pinned version)
- **Docker named volume**: Lego state stored in Docker-managed volume `lego_data` (no host mount issues)
- **Systemd timer runs on host**: Timer executes `docker compose run` to trigger renewal in container
- **Same-host deployment**: Since lego and Traefik are on same host, uses direct file copy (no SSH)
- **Wildcard certificate**: Covers `*.exnada.com` and `exnada.com` in single certificate
- **Certificate renewal**: Renews 30 days before expiry
- **Atomic deployment**: Copy to `.tmp`, verify, then `mv` into place
- **Rollback on failure**: Backs up existing certs, restores if reload fails
- **All operations logged**: Systemd journal for host operations, container logs for lego

## License

Proprietary - All Rights Reserved, ExNada Inc.
