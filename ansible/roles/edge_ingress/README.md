# edge_ingress Role

Deploys Traefik as an HTTPS ingress router for private services via Tailscale, using Traefik's built-in ACME resolver with GoDaddy DNS-01 challenge for automatic Let's Encrypt certificate management.

## What This Role Does

- Installs and configures Traefik in Docker
- Configures HTTP→HTTPS redirect
- Uses Traefik's built-in ACME resolver with GoDaddy DNS-01 challenge for automatic certificate issuance and renewal
- Configures host-based routing for private services
- Adds security headers middleware
- Integrates with firewall (opens HTTP/HTTPS ports on `tailscale0` interface)
- Detects Tailscale tailnet name and constructs FQDNs for backend services

## Requirements

- Debian distribution (tested on Debian trixie/testing)
- Ansible 2.9+
- Root/sudo access (role uses `become: true`)
- **Tailscale must be installed and connected** (via `tailscale` role)
- Docker must be installed (via `docker_host` role)
- **GoDaddy API credentials** must be configured in `all_secrets.yml` (`godaddy_api_key` and `godaddy_api_secret`)
- Domain must be managed by GoDaddy DNS
- Ports 80 and 443 must be available

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `edge_ingress_enabled` | `false` | Enable this role (set to `true` in host_vars) |
| `edge_ingress_domain` | `exnada.com` | Base domain for routing |
| `edge_ingress_acme_email` | `admin@exnada.com` | Email for Let's Encrypt ACME registration |
| `edge_ingress_use_tailscale_fqdn` | `true` | Use Tailscale FQDNs for backend services (e.g., `http://rigel.tailb821ac.ts.net:8000`) |
| `edge_ingress_tailnet_name` | `""` | Tailscale tailnet name (auto-detected if empty) |
| `edge_ingress_backend_timeout_connect` | `30s` | Backend connection timeout |
| `edge_ingress_backend_timeout_response` | `60s` | Backend response timeout |
| `edge_ingress_health_check_interval` | `10s` | Health check interval |
| `edge_ingress_health_check_timeout` | `3s` | Health check timeout |
| `edge_ingress_health_check_failure_threshold` | `3` | Health check failure threshold |
| `edge_ingress_container_name` | `traefik` | Docker container name for Traefik |
| `edge_ingress_data_dir` | `/opt/traefik` | Directory for Traefik configuration and data |
| `edge_ingress_routes` | `[]` | List of route configurations (see examples below) |
| `edge_ingress_disable_tls` | `false` | Disable TLS (for testing only) |

## Route Configuration

Each route in `edge_ingress_routes` must have:

- `host`: Hostname to route (e.g., `mpnas.exnada.com`)
- `backend`: Backend service URL (e.g., `http://mpnas:5000` or `http://vega:8000`)
- `health_path`: Health check path (optional, e.g., `/health`). If omitted, health checks are disabled for this route.

### Backend URL Resolution

If `edge_ingress_use_tailscale_fqdn: true` (default):
- Backend hostnames are resolved to Tailscale FQDNs
- Example: `http://rigel:8000` → `http://rigel.tailb821ac.ts.net:8000`

If `edge_ingress_use_tailscale_fqdn: false`:
- Backend URLs are used as-is
- Useful for local services or IP addresses

## Dependencies

- **tailscale**: Must run before this role (Tailscale must be connected)
- **docker_host**: Docker must be installed
- **firewall_nftables**: Should run after this role to open HTTP/HTTPS ports (or set `edge_ingress_enabled: true` before firewall)
- **internal_dns**: Recommended for DNS resolution of private hosts

## Usage Examples

### Basic Usage

```yaml
# In host_vars/rigel.yml
edge_ingress_enabled: true
edge_ingress_domain: exnada.com
edge_ingress_acme_email: admin@exnada.com
edge_ingress_routes:
  - host: mpnas.exnada.com
    backend: http://mpnas:5000
    # No health_path - service doesn't provide health endpoint
  - host: aispector.exnada.com
    backend: http://vega:8000
    health_path: /health
  - host: dev.exnada.com
    backend: http://rigel:8000
    health_path: /health
```

### With Custom Timeouts

```yaml
edge_ingress_enabled: true
edge_ingress_domain: exnada.com
edge_ingress_backend_timeout_connect: 60s
edge_ingress_backend_timeout_response: 120s
edge_ingress_routes:
  - host: slow-service.exnada.com
    backend: http://slow-host:8080
    health_path: /health
```

### Without Tailscale FQDN Resolution

```yaml
edge_ingress_enabled: true
edge_ingress_use_tailscale_fqdn: false
edge_ingress_routes:
  - host: local.exnada.com
    backend: http://127.0.0.1:3000
    health_path: /health
```

## Certificate Management

This role uses **Traefik's built-in ACME resolver** with GoDaddy DNS-01 challenge for automatic Let's Encrypt certificate management.

### Automatic Certificate Issuance and Renewal

- Traefik automatically obtains certificates from Let's Encrypt when routes are first accessed
- Certificates are automatically renewed before expiration (30 days before expiry)
- Certificates are stored in `/opt/traefik/acme.json` (600 permissions, root:root)
- Uses DNS-01 challenge via GoDaddy DNS API (no need to expose ports 80/443 to the internet)
- Supports both staging and production Let's Encrypt environments (controlled by `cert_issuer_ca_server`)

### Configuration

- **GoDaddy API Credentials**: Set `godaddy_api_key` and `godaddy_api_secret` in `all_secrets.yml`
- **CA Server**: Set `cert_issuer_ca_server: staging` for testing or `cert_issuer_ca_server: production` for real certificates
- **Email**: Set `edge_ingress_acme_email` for Let's Encrypt account registration

### Certificate Storage

- ACME account and certificates are stored in `/opt/traefik/acme.json`
- File permissions: 600 (root:root)
- Automatically created by the role if it doesn't exist

## How It Works

1. **Tailnet Detection**: Automatically detects Tailscale tailnet name from `tailscale status --json`
2. **Backend Resolution**: Converts backend hostnames to Tailscale FQDNs (if enabled)
3. **ACME Certificate Management**: Traefik automatically obtains and renews Let's Encrypt certificates via GoDaddy DNS-01 challenge
4. **Traefik Deployment**: Runs Traefik in Docker container with `network_mode: host`
5. **Firewall Integration**: Sets `edge_ingress_enabled: true` which opens HTTP/HTTPS ports on `tailscale0` interface

## Features

### Automatic HTTPS

- HTTP requests are automatically redirected to HTTPS
- Automatic Let's Encrypt certificate issuance via Traefik's built-in ACME resolver
- GoDaddy DNS-01 challenge (no need to expose ports to internet)
- Automatic certificate renewal before expiration

### Security Headers

Traefik automatically adds security headers:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Strict-Transport-Security: max-age=31536000`

### Health Checks

Each route includes health checks:
- Interval: `edge_ingress_health_check_interval`
- Timeout: `edge_ingress_health_check_timeout`
- Failure threshold: `edge_ingress_health_check_failure_threshold`

### Retry Middleware

Automatic retry on backend failures (3 attempts).

## Firewall Integration

When `edge_ingress_enabled: true`, the `firewall_nftables` role automatically opens:
- TCP port 80 on `tailscale0` interface (HTTP)
- TCP port 443 on `tailscale0` interface (HTTPS)

## Troubleshooting

### Traefik Container Not Starting

1. **Check Docker is running**:
   ```bash
   sudo systemctl status docker
   ```

2. **Check Traefik logs**:
   ```bash
   docker logs traefik
   ```

3. **Check ports 80/443 are available**:
   ```bash
   sudo netstat -tuln | grep -E ':(80|443) '
   ```

4. **Check configuration files**:
   ```bash
   sudo cat /opt/traefik/traefik.yml
   sudo cat /opt/traefik/dynamic.yml
   ```

### SSL Certificate Not Issued

1. **Check ACME logs**:
   ```bash
   docker logs traefik | grep -i acme
   ```

2. **Verify certificates are present**:
   ```bash
   ls -la /opt/traefik/certs/
   # Should show exnada.com.crt and exnada.com.key
   ```

3. **Check certificate issuer status**:
   ```bash
   sudo systemctl status lego-renew.timer
   sudo journalctl -u lego-renew.service -n 50
   ```

### Backend Not Reachable

1. **Check backend service is running**:
   ```bash
   # On backend host
   curl http://localhost:8000/health
   ```

2. **Check Tailscale connectivity**:
   ```bash
   tailscale ping rigel
   ```

3. **Verify backend URL resolution**:
   - If using Tailscale FQDNs, check `rigel.tailb821ac.ts.net` resolves
   - If not, check backend hostname resolves

4. **Check Traefik routing**:
   ```bash
   docker logs traefik | grep -i route
   ```

### HTTP Not Redirecting to HTTPS

1. **Check Traefik configuration**:
   ```bash
   sudo cat /opt/traefik/traefik.yml | grep -A 5 redirections
   ```

2. **Check Traefik logs**:
   ```bash
   docker logs traefik | grep -i redirect
   ```

3. **Test HTTP request**:
   ```bash
   curl -I http://mpnas.exnada.com
   # Should return 301 or 308 redirect
   ```

## Configuration Files

### Static Configuration

Location: `{{ edge_ingress_data_dir }}/traefik.yml`

Contains:
- Entrypoints (HTTP/HTTPS)
- ACME certificate resolver configuration (GoDaddy DNS-01 challenge)
- File provider configuration

### Dynamic Configuration

Location: `{{ edge_ingress_data_dir }}/dynamic.yml`

Contains:
- Routers (host-based routing with `certResolver: letsencrypt`)
- Services (backend URLs)
- Middlewares (security headers, retry)

### Docker Compose

Location: `{{ edge_ingress_data_dir }}/docker-compose.yml`

Defines:
- Traefik container
- Network mode: `host` (required for ports 80/443)
- Volume mounts for configuration and ACME storage
- GoDaddy API credentials as environment variables

### ACME Storage

Location: `{{ edge_ingress_data_dir }}/acme.json`

Stores:
- Let's Encrypt SSL certificates
- ACME account information
- Permissions: 600 (root:root)
- Automatically created by the role if it doesn't exist

## Security Considerations

- **Tailscale Only**: HTTP/HTTPS are only accessible on `tailscale0` interface (via firewall)
- **ACME Storage**: `acme.json` has 600 permissions (only root can read)
- **GoDaddy API Credentials**: Stored securely in `all_secrets.yml` and passed as environment variables to Traefik container
- **Security Headers**: Automatically added to all responses
- **No Dashboard**: Traefik dashboard is not exposed (insecure: false)
- **DNS-01 Challenge**: No need to expose ports 80/443 to the internet (certificates obtained via DNS)

## Notes

- The role is idempotent: running it multiple times produces no changes
- Tailnet name is detected automatically on each run
- Backend URLs are resolved to Tailscale FQDNs if enabled
- Traefik's built-in ACME resolver automatically obtains and renews Let's Encrypt certificates
- Certificates are obtained on-demand when routes are first accessed
- Certificates are automatically renewed 30 days before expiration
- Health checks are configured for all routes (if `health_path` is specified)
- Retry middleware is enabled for all routes

## Integration with Other Roles

- **tailscale**: Must run before this role
- **docker_host**: Docker must be installed
- **firewall_nftables**: Opens HTTP/HTTPS ports when `edge_ingress_enabled: true`
- **internal_dns**: Recommended for DNS resolution of private hosts
- **cert_issuer**: Optional - can be disabled if using Traefik's built-in ACME resolver (current approach)

## License

Proprietary - All Rights Reserved, ExNada Inc.
