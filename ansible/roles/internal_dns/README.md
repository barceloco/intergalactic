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

## Dependencies

- **tailscale**: Must run before this role (Tailscale must be connected)
- **docker_host**: Docker must be installed
- **firewall_nftables**: Should run after this role to open DNS ports (or set `internal_dns_enabled: true` before firewall)

## DNS Configuration

### Authoritative Zone

The role creates an authoritative DNS zone for `{{ internal_dns_domain }}` with:
- SOA record
- NS record
- A records for each host in `internal_dns_private_hosts` (resolving to Tailscale IP)

### Upstream Forwarding

All queries not in the authoritative zone are forwarded to `internal_dns_upstream_servers`.

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
2. **Zone File Generation**: Creates DNS zone file with A records for each private host
3. **CoreDNS Configuration**: Configures CoreDNS with:
   - `file` plugin for authoritative zone
   - `forward` plugin for upstream queries
4. **Docker Deployment**: Runs CoreDNS in Docker container with `network_mode: host`
5. **Firewall Integration**: Sets `internal_dns_enabled: true` which opens DNS ports on `tailscale0` interface

## DNS Records Created

For each host in `internal_dns_private_hosts`, the role creates:
- **A record**: `{hostname}.{domain}` → Tailscale IPv4 address

Example with `internal_dns_private_hosts: [mpnas, aispector]`:
```
mpnas.exnada.com.    IN  A  100.x.x.x
aispector.exnada.com. IN  A  100.x.x.x
```

## Tailscale Split DNS

This role is designed for Tailscale Split DNS:

1. Configure Tailscale Split DNS to use this server for `{{ internal_dns_domain }}`
2. Private subdomains resolve to Tailscale IPs
3. All other queries forward to upstream DNS servers

## Firewall Integration

When `internal_dns_enabled: true`, the `firewall_nftables` role automatically opens:
- UDP port 53 on `tailscale0` interface
- TCP port 53 on `tailscale0` interface

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

## Configuration Files

### Corefile

Location: `{{ internal_dns_data_dir }}/Corefile`

Contains:
- Zone configuration for `{{ internal_dns_domain }}`
- Upstream forwarders configuration

### Zone File

Location: `{{ internal_dns_data_dir }}/db.{{ internal_dns_domain }}`

Contains:
- SOA record
- NS record
- A records for each private host

### Docker Compose

Location: `{{ internal_dns_data_dir }}/docker-compose.yml`

Defines:
- CoreDNS container
- Network mode: `host` (required for port 53)
- Volume mounts for configuration

## Notes

- The role is idempotent: running it multiple times produces no changes
- Tailscale IP is detected automatically on each run
- Zone file is regenerated if `internal_dns_private_hosts` changes
- CoreDNS uses `network_mode: host` to bind to port 53
- DNS queries are only accessible via Tailscale network (firewall restricts to `tailscale0`)
- The role validates Tailscale connectivity before proceeding

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

MIT
