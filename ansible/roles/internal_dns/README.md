# internal_dns Role

Deploys CoreDNS as an internal DNS server for private subdomains via Tailscale Split DNS, providing authoritative DNS for selected hosts while forwarding other queries upstream.

## What This Role Does

- Installs and configures CoreDNS in Docker
- Detects Tailscale IPv4 address automatically
- Serves authoritative DNS for private subdomains (e.g., `mpnas.exnada.com`, `aispector.exnada.com`)
- Forwards all other queries to upstream DNS servers
- Listens on UDP/TCP port 53
- Integrates with firewall (opens DNS ports on `tailscale0` interface)

## Requirements

- Debian distribution (tested on Debian trixie/testing)
- Ansible 2.9+
- Root/sudo access (role uses `become: true`)
- **Tailscale must be installed and connected** (via `tailscale` role)
- Docker must be installed (via `docker_host` role)
- Port 53 must be available (not used by systemd-resolved or other DNS servers)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `internal_dns_enabled` | `false` | Enable this role (set to `true` in host_vars) |
| `internal_dns_domain` | `exnada.com` | Base domain for private subdomains |
| `internal_dns_private_hosts` | `[]` | List of hostnames to create A records for (e.g., `[mpnas, aispector, dev]`) |
| `internal_dns_upstream_servers` | `["8.8.8.8", "8.8.4.4"]` | Upstream DNS servers for forwarding queries |
| `internal_dns_container_name` | `coredns` | Docker container name for CoreDNS |
| `internal_dns_data_dir` | `/opt/coredns` | Directory for CoreDNS configuration and data |
| `internal_dns_cache_ttl` | `3600` | Cache TTL in seconds for DNS responses |
| `internal_dns_health_port` | `8080` | Port for health check endpoint |
| `internal_dns_ready_port` | `8181` | Port for readiness check endpoint |
| `internal_dns_prometheus_port` | `9153` | Port for Prometheus metrics endpoint |
| `internal_dns_reload_port` | `8182` | Port for config reload endpoint |

## Dependencies

- **tailscale**: Must be installed and connected BEFORE this role runs (typically installed in foundation phase)
- **docker_host**: Docker must be installed
- **firewall_nftables**: Should run after this role to open DNS ports (or set `internal_dns_enabled: true` before firewall)

**Note**: This role does NOT install Tailscale. Tailscale must be installed in the foundation phase before running production.

## DNS Configuration

### Split-Horizon DNS (Fallthrough Behavior)

CoreDNS uses a **split-horizon** approach:

1. **Internal Hosts** (authoritative): Queries for hosts in `internal_dns_private_hosts` return Tailscale IPs with the **AA (Authoritative Answer)** flag set
2. **External/Unknown Subdomains** (forwarded): All other queries (e.g., `www.exnada.com`, `mail.exnada.com`, `foo.exnada.com`) are forwarded to upstream DNS servers recursively (no AA flag)

**How Fallthrough Works**:
- The `template` plugin only matches exact hostnames in `internal_dns_private_hosts`
- Non-matching queries automatically fall through to the `forward` plugin
- The `forward` plugin queries upstream DNS servers (8.8.8.8, 8.8.4.4) recursively
- This ensures `www.exnada.com` and other external subdomains resolve via public DNS while internal hosts resolve to Tailscale IPs

**Example**:
- `aispector.exnada.com` → Returns Tailscale IP (authoritative, AA flag)
- `www.exnada.com` → Forwards to public DNS (recursive, no AA flag)
- `mail.exnada.com` → Forwards to public DNS (recursive, no AA flag)
- `foo.exnada.com` → Forwards to public DNS (recursive, no AA flag)

### Authoritative Zone

The role creates authoritative DNS records for hosts in `internal_dns_private_hosts`:
- A records for each host (resolving to Tailscale IPv4 address)
- Records are served with the AA (Authoritative Answer) flag

### Upstream Forwarding

All queries not matching internal hosts are forwarded to `internal_dns_upstream_servers` recursively. CoreDNS acts as a recursive forwarder for these queries (no AA flag).

## Usage Examples

### Basic Usage

```yaml
# In host_vars/rigel.yml
internal_dns_enabled: true
internal_dns_domain: exnada.com
internal_dns_private_hosts:
  - mpnas
  - aispector
  - dev
```

This creates:
- `mpnas.exnada.com` → Tailscale IP
- `aispector.exnada.com` → Tailscale IP
- `dev.exnada.com` → Tailscale IP

### Custom Upstream Servers

```yaml
internal_dns_enabled: true
internal_dns_domain: exnada.com
internal_dns_private_hosts:
  - mpnas
internal_dns_upstream_servers:
  - 1.1.1.1
  - 1.0.0.1
```

## How It Works

1. **Tailscale IP Detection**: Automatically detects Tailscale IPv4 address using `tailscale ip -4`
2. **CoreDNS Configuration**: Configures CoreDNS with:
   - `template` plugin for authoritative internal hosts (A records only)
   - `cache` plugin for response caching (configurable TTL)
   - `loop` plugin to prevent forwarding loops
   - `forward` plugin for upstream queries (unknown subdomains)
   - `health`, `ready`, `prometheus`, and `reload` plugins for monitoring and management
3. **Docker Deployment**: Runs CoreDNS in Docker container with `network_mode: host`
4. **Firewall Integration**: Sets `internal_dns_enabled: true` which opens DNS ports on `tailscale0` interface
5. **Fallthrough**: Unknown subdomains automatically forward to upstream DNS servers

## DNS Records Created

For each host in `internal_dns_private_hosts`, the role creates:
- **A record**: `{hostname}.{domain}` → Tailscale IPv4 address

Example with `internal_dns_private_hosts: [mpnas, aispector]`:
```
mpnas.exnada.com.    IN  A  100.x.x.x
aispector.exnada.com. IN  A  100.x.x.x
```

## Tailscale Split DNS Configuration

This role requires Tailscale Split DNS to be configured in the Tailscale admin console:

1. **Go to Tailscale Admin Console**: https://login.tailscale.com/admin/dns
2. **Add Split DNS Configuration**:
   - Domain: `exnada.com` (or your `internal_dns_domain`)
   - Nameserver: `rigel.tailb821ac.ts.net` (or the Tailscale IP: `100.72.27.93`)
3. **Save the configuration**
4. **Wait for DNS config to propagate** (usually a few minutes)

**Result**:
- All queries for `exnada.com` and its subdomains are routed to this CoreDNS server
- Internal hosts (`mpnas`, `aispector`, `dev`) resolve to Tailscale IPs
- External subdomains (`www`, `mail`, etc.) forward to public DNS
- Unknown subdomains forward to public DNS

## Firewall Integration

When `internal_dns_enabled: true`, the `firewall_nftables` role automatically opens:
- UDP port 53 on `tailscale0` interface (DNS queries)
- TCP port 53 on `tailscale0` interface (DNS over TCP)

**Monitoring Ports** (protected by firewall):
- Port 8080 (health endpoint) - Only accessible via Tailscale interface
- Port 8181 (ready endpoint) - Only accessible via Tailscale interface
- Port 9153 (Prometheus metrics) - Only accessible via Tailscale interface
- Port 8182 (reload endpoint) - Only accessible via Tailscale interface

The firewall's default DROP policy and `iifname "tailscale0" accept` rule ensure these ports are **not exposed to the open internet** - only accessible via Tailscale network.

## Troubleshooting

### CoreDNS Container Not Starting

1. **Check Docker is running**:
   ```bash
   sudo systemctl status docker
   ```

2. **Check CoreDNS logs**:
   ```bash
   docker logs coredns
   ```

3. **Check port 53 is available**:
   ```bash
   sudo netstat -tuln | grep :53
   sudo ss -tuln | grep :53
   ```

4. **Check configuration files**:
   ```bash
   sudo cat /opt/coredns/Corefile
   sudo cat /opt/coredns/db.exnada.com
   ```

### DNS Not Resolving

1. **Check CoreDNS is running**:
   ```bash
   docker ps | grep coredns
   ```

2. **Test DNS resolution locally**:
   ```bash
   dig @127.0.0.1 mpnas.exnada.com
   ```

3. **Check Tailscale IP detection**:
   ```bash
   tailscale ip -4
   ```

4. **Verify zone file**:
   ```bash
   sudo cat /opt/coredns/db.exnada.com
   ```

### Tailscale IP Detection Failed

1. **Check Tailscale is connected**:
   ```bash
   tailscale status
   ```

2. **Check Tailscale has IPv4**:
   ```bash
   tailscale ip -4
   ```

3. **Verify enable_tailscale is true**:
   - Check `group_vars/all.yml` or `host_vars/{hostname}.yml`

### Port 53 Already in Use

If systemd-resolved or another DNS server is using port 53:

1. **Disable systemd-resolved** (if not needed):
   ```bash
   sudo systemctl stop systemd-resolved
   sudo systemctl disable systemd-resolved
   ```

2. **Or configure CoreDNS to use different port** (requires template modification)

## Development Workflow

### Fast Iteration (Development)

For rapid development and testing, use the direct script instead of running the full Ansible pipeline:

1. **Edit Corefile directly on rigel**:
   ```bash
   ssh rigel
   sudo vim /opt/coredns/Corefile
   ```

2. **Test config and restart**:
   ```bash
   # Run the development test script
   sudo ./scripts/test-coredns-config.sh
   
   # Or manually:
   docker compose -f /opt/coredns/docker-compose.yml restart
   dig @127.0.0.1 www.exnada.com
   ```

3. **Validate changes**:
   ```bash
   ./scripts/validate-coredns-split-dns.sh
   ```

4. **When ready, commit and deploy via Ansible**:
   ```bash
   # Edit template in repo
   vim ansible/roles/internal_dns/templates/Corefile.j2
   
   # Deploy
   ./scripts/run-ansible.sh prod rigel production --tags services
   ```

**Key Benefit**: Fast feedback loop during development, no Ansible overhead.

### Production Validation

After deployment, run comprehensive validation:

```bash
# From any machine with Tailscale access
./scripts/validate-coredns-split-dns.sh [COREDNS_IP]
# Default: 100.72.27.93 (rigel's Tailscale IP)
```

The validation script tests:
- Internal hosts resolve to Tailscale IPs
- External subdomains forward to public DNS
- Unknown subdomains forward to public DNS
- Health/ready endpoints respond
- Prometheus metrics available
- Cache behavior

## Configuration Files

### Corefile

Location: `{{ internal_dns_data_dir }}/Corefile`

Contains:
- Zone configuration for `{{ internal_dns_domain }}` with `template` plugin for internal hosts
- `cache` plugin for response caching
- `loop` plugin to prevent forwarding loops
- `forward` plugin for upstream queries
- `health`, `ready`, `prometheus`, and `reload` plugin endpoints

### Zone File

Location: `{{ internal_dns_data_dir }}/db.{{ internal_dns_domain }}`

**Note**: This file is generated but not actively used in the current configuration. The `template` plugin serves internal hosts directly without requiring a zone file. The file is kept for reference and potential future use.

### Docker Compose

Location: `{{ internal_dns_data_dir }}/docker-compose.yml`

Defines:
- CoreDNS container
- Network mode: `host` (required for port 53)
- Volume mounts for configuration

## Notes

- The role is idempotent: running it multiple times produces no changes
- Tailscale IP is detected automatically on each run
- CoreDNS uses `network_mode: host` to bind to port 53 and monitoring ports
- DNS queries are only accessible via Tailscale network (firewall restricts to `tailscale0`)
- Monitoring ports (8080, 8181, 9153, 8182) are protected by firewall (Tailscale-only access)
- The role validates Tailscale connectivity before proceeding
- Unknown subdomains automatically forward to upstream DNS (fallthrough behavior)
- IPv4-only: AAAA (IPv6) records are not supported (simplifies configuration)

## Security Considerations

- **Tailscale Only**: DNS is only accessible on `tailscale0` interface (via firewall)
- **Authoritative Zone**: Only serves records for configured private hosts
- **Upstream Forwarding**: All other queries forward to trusted upstream servers
- **No Recursion**: CoreDNS does not perform recursive queries (only forwards)

## Integration with Other Roles

- **tailscale**: Must run before this role
- **docker_host**: Docker must be installed
- **firewall_nftables**: Opens DNS ports when `internal_dns_enabled: true`

## License

Proprietary - All Rights Reserved, ExNada Inc.
