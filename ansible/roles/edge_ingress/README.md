# edge_ingress Role

Deploys Traefik as an HTTPS ingress router for private services via Tailscale, providing automatic SSL certificate management via ACME DNS-01 challenge with Hostinger DNS provider.

## What This Role Does

- Installs and configures Traefik in Docker
- Configures HTTP→HTTPS redirect
- Sets up ACME DNS-01 challenge with Let's Encrypt
- Uses Hostinger DNS provider for wildcard certificate management
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
- **Hostinger API token** must be configured in `all_secrets.yml`
- Ports 80 and 443 must be available
- Domain must be managed by Hostinger DNS

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `edge_ingress_enabled` | `false` | Enable this role (set to `true` in host_vars) |
| `edge_ingress_domain` | `exnada.com` | Base domain for routing |
| `edge_ingress_acme_email` | `admin@exnada.com` | Email for Let's Encrypt ACME registration |
| `edge_ingress_use_tailscale_fqdn` | `true` | Use Tailscale FQDNs for backend services (e.g., `http://rigel.tailnet-name.ts.net:8000`) |
| `edge_ingress_tailnet_name` | `""` | Tailscale tailnet name (auto-detected if empty) |
| `edge_ingress_backend_timeout_connect` | `30s` | Backend connection timeout |
| `edge_ingress_backend_timeout_response` | `60s` | Backend response timeout |
| `edge_ingress_health_check_interval` | `10s` | Health check interval |
| `edge_ingress_health_check_timeout` | `3s` | Health check timeout |
| `edge_ingress_health_check_failure_threshold` | `3` | Health check failure threshold |
| `edge_ingress_container_name` | `traefik` | Docker container name for Traefik |
| `edge_ingress_data_dir` | `/opt/traefik` | Directory for Traefik configuration and data |
| `edge_ingress_routes` | `[]` | List of route configurations (see examples below) |
| `hostinger_api_token` | (required) | Hostinger DNS API token (from `all_secrets.yml`) |

## Route Configuration

Each route in `edge_ingress_routes` must have:

- `host`: Hostname to route (e.g., `mpnas.exnada.com`)
- `backend`: Backend service URL (e.g., `http://mpnas:5000` or `http://vega:8000`)
- `health_path`: Health check path (e.g., `/health`)

### Backend URL Resolution

If `edge_ingress_use_tailscale_fqdn: true` (default):
- Backend hostnames are resolved to Tailscale FQDNs
- Example: `http://rigel:8000` → `http://rigel.tailnet-name.ts.net:8000`

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
    health_path: /health
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

## Secrets Configuration

The Hostinger API token must be configured in `all_secrets.yml`:

```yaml
# In ansible/inventories/prod/group_vars/all_secrets.yml
hostinger_api_token: "your-actual-api-token-here"
```

Get your API token from: https://hpanel.hostinger.com/api

## How It Works

1. **Tailnet Detection**: Automatically detects Tailscale tailnet name from `tailscale status --json`
2. **Backend Resolution**: Converts backend hostnames to Tailscale FQDNs (if enabled)
3. **ACME Configuration**: Configures Let's Encrypt with Hostinger DNS-01 challenge
4. **Certificate Management**: Requests wildcard certificate for `{{ domain }}` and `*.{{ domain }}`
5. **Traefik Deployment**: Runs Traefik in Docker container with `network_mode: host`
6. **Firewall Integration**: Sets `edge_ingress_enabled: true` which opens HTTP/HTTPS ports on `tailscale0` interface

## Features

### Automatic HTTPS

- HTTP requests are automatically redirected to HTTPS
- Wildcard SSL certificates via Let's Encrypt
- Automatic certificate renewal
- DNS-01 challenge (no need to expose ports publicly)

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

2. **Verify Hostinger API token**:
   - Check `all_secrets.yml` has valid token
   - Test token: https://hpanel.hostinger.com/api

3. **Check DNS propagation**:
   ```bash
   dig _acme-challenge.exnada.com TXT
   ```

4. **Verify domain is managed by Hostinger**:
   - Check Hostinger DNS panel

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
   - If using Tailscale FQDNs, check `rigel.tailnet-name.ts.net` resolves
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
- ACME configuration
- File provider configuration

### Dynamic Configuration

Location: `{{ edge_ingress_data_dir }}/dynamic.yml`

Contains:
- Routers (host-based routing)
- Services (backend URLs)
- Middlewares (security headers, retry)

### Docker Compose

Location: `{{ edge_ingress_data_dir }}/docker-compose.yml`

Defines:
- Traefik container
- Network mode: `host` (required for ports 80/443)
- Volume mounts for configuration and ACME storage

### ACME Storage

Location: `{{ edge_ingress_data_dir }}/acme.json`

Stores:
- SSL certificates
- ACME account information
- Permissions: 600 (root:root)

## Security Considerations

- **Tailscale Only**: HTTP/HTTPS are only accessible on `tailscale0` interface (via firewall)
- **ACME Storage**: `acme.json` has 600 permissions (only root can read)
- **Security Headers**: Automatically added to all responses
- **No Dashboard**: Traefik dashboard is not exposed (insecure: false)
- **Wildcard Certificates**: Single certificate for domain and all subdomains

## Notes

- The role is idempotent: running it multiple times produces no changes
- Tailnet name is detected automatically on each run
- Backend URLs are resolved to Tailscale FQDNs if enabled
- ACME certificates are automatically renewed by Traefik
- The role validates Hostinger API token and routes before proceeding
- Health checks are configured for all routes
- Retry middleware is enabled for all routes

## Integration with Other Roles

- **tailscale**: Must run before this role
- **docker_host**: Docker must be installed
- **firewall_nftables**: Opens HTTP/HTTPS ports when `edge_ingress_enabled: true`
- **internal_dns**: Recommended for DNS resolution of private hosts

## License

MIT
