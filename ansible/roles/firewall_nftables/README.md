# firewall_nftables Role

Configures nftables firewall with default-deny policy and explicit allow rules for specified ports and services.

## What This Role Does

- Installs `nftables` package
- Deploys firewall rules based on configured ports and services
- Enables and starts nftables service
- Validates firewall configuration syntax
- Integrates with Tailscale (allows SSH, DNS, HTTP, HTTPS on `tailscale0` interface)
- Integrates with docker_deploy (merges `docker_deploy_tcp_ports` into allowed ports)

## Requirements

- Debian distribution (tested on Debian trixie/testing)
- Ansible 2.9+
- Root/sudo access (role uses `become: true`)
- Network access for package installation

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `firewall_allow_tcp_ports` | `[22]` | List of TCP ports to allow (SSH port 22 is always included) |
| `firewall_allow_udp_ports` | `[]` | List of UDP ports to allow (Tailscale UDP 41641 added if `enable_tailscale: true`) |
| `firewall_rate_limit` | `10` | Rate limit for dropped packets (packets/second) |
| `ssh_port` | `22` | SSH port number (used in firewall rules) |
| `enable_tailscale` | `false` | Enable Tailscale-specific firewall rules |
| `internal_dns_enabled` | `false` | Enable DNS ports (53 TCP/UDP) on Tailscale interface |
| `edge_ingress_enabled` | `false` | Enable HTTP/HTTPS ports (80/443 TCP) on Tailscale interface |
| `docker_deploy_tcp_ports` | `[]` | Automatically merged into `firewall_allow_tcp_ports` (from docker_deploy role) |

## Firewall Rules

### Default Policy
- **Input**: DROP (default-deny)
- **Forward**: DROP
- **Output**: ACCEPT

### Always Allowed
- Loopback traffic (`lo` interface)
- Established and related connections
- SSH port (from `ssh_port` variable, default 22)

### Conditionally Allowed (Based on Variables)

**Tailscale Interface (`tailscale0`)** - If `enable_tailscale: true`:
- SSH (port from `ssh_port`)
- DNS (53 TCP/UDP) - If `internal_dns_enabled: true`
- HTTP (80 TCP) - If `edge_ingress_enabled: true`
- HTTPS (443 TCP) - If `edge_ingress_enabled: true`

**All Interfaces**:
- TCP ports from `firewall_allow_tcp_ports`
- UDP ports from `firewall_allow_udp_ports`
- Tailscale UDP 41641 (if `enable_tailscale: true`)

### Rate Limiting
- Dropped packets are rate-limited to prevent log flooding
- Rate limit: `firewall_rate_limit` packets/second (default: 10)

## Dependencies

- **docker_deploy**: If used, `docker_deploy_tcp_ports` are automatically merged into allowed ports
- **tailscale**: Should run before this role if Tailscale is enabled

## Usage Examples

### Basic Usage (SSH Only)

```yaml
# In group_vars/all.yml or host_vars
firewall_allow_tcp_ports:
  - "{{ ssh_port }}"
```

### With Additional Ports

```yaml
firewall_allow_tcp_ports:
  - "{{ ssh_port }}"
  - 8000   # API
  - 5432   # PostgreSQL
  - 6379   # Redis
```

### With Tailscale

```yaml
enable_tailscale: true
internal_dns_enabled: true
edge_ingress_enabled: true
firewall_allow_tcp_ports:
  - "{{ ssh_port }}"
```

This automatically allows:
- SSH on `tailscale0` interface
- DNS (53 TCP/UDP) on `tailscale0` interface
- HTTP (80 TCP) on `tailscale0` interface
- HTTPS (443 TCP) on `tailscale0` interface

### With Docker Deploy Integration

```yaml
# In host_vars/rigel.yml
enable_docker_deploy: true
docker_deploy_tcp_ports:
  - 8000
  - 5432
  - 6379

# firewall_nftables automatically picks up docker_deploy_tcp_ports
```

## Firewall Rule Template

The role uses `templates/nftables.conf.j2` to generate firewall rules. The template:

1. Sets default policies (DROP for input/forward, ACCEPT for output)
2. Allows loopback traffic
3. Allows established/related connections
4. Allows SSH port
5. Conditionally allows Tailscale interface rules
6. Allows configured TCP/UDP ports
7. Applies rate limiting to dropped packets

## Security Considerations

- **Default-Deny Policy**: All traffic is denied by default, only explicitly allowed ports are open
- **Tailscale Isolation**: Tailscale services (DNS, HTTP, HTTPS) are only accessible on `tailscale0` interface
- **Rate Limiting**: Prevents log flooding from dropped packets
- **SSH Protection**: SSH is always allowed (required for management)

## Troubleshooting

### Cannot Access Services After Firewall Applied

1. **Check if port is in allowed list**:
   ```bash
   sudo nft list ruleset | grep -A 5 "tcp dport"
   ```

2. **Check if service is listening**:
   ```bash
   sudo ss -tlnp | grep :8000
   ```

3. **Check firewall status**:
   ```bash
   sudo systemctl status nftables
   sudo nft list ruleset
   ```

### Firewall Configuration Syntax Error

1. **Check syntax manually**:
   ```bash
   sudo nft -c -f /etc/nftables.conf
   ```

2. **Check template variables**:
   - Verify `firewall_allow_tcp_ports` is a list
   - Verify `ssh_port` is a number
   - Check for YAML syntax errors in inventory

3. **View generated configuration**:
   ```bash
   sudo cat /etc/nftables.conf
   ```

### Cannot Access Tailscale Services

1. **Check Tailscale interface exists**:
   ```bash
   ip addr show tailscale0
   ```

2. **Check Tailscale rules**:
   ```bash
   sudo nft list ruleset | grep tailscale0
   ```

3. **Verify variables are set**:
   - `enable_tailscale: true`
   - `internal_dns_enabled: true` (for DNS)
   - `edge_ingress_enabled: true` (for HTTP/HTTPS)

### Firewall Not Starting

1. **Check service status**:
   ```bash
   sudo systemctl status nftables
   sudo journalctl -u nftables
   ```

2. **Check configuration syntax**:
   ```bash
   sudo nft -c -f /etc/nftables.conf
   ```

3. **Test rules manually**:
   ```bash
   sudo nft -f /etc/nftables.conf
   ```

## Advanced Usage

### Custom Firewall Rules

To add custom firewall rules, you can:

1. **Extend the template**: Modify `templates/nftables.conf.j2`
2. **Use a custom template**: Override `templates/nftables.conf.j2` in your playbook
3. **Add rules after role**: Use `post_tasks` to add additional rules

Example custom rule:
```yaml
- name: Add custom firewall rule
  command: nft add rule inet filter input tcp dport 9000 accept
  when: ansible_facts['os_family'] == 'Debian'
```

## Notes

- The role is idempotent: running it multiple times produces no changes
- Firewall rules are applied immediately when the role runs
- Configuration is validated before applying
- `docker_deploy_tcp_ports` are automatically merged (no manual configuration needed)
- Tailscale interface rules are only added if `enable_tailscale: true`
- Rate limiting helps prevent log flooding but may hide some attack patterns

## Integration with Other Roles

- **docker_deploy**: Automatically merges `docker_deploy_tcp_ports`
- **tailscale**: Should run before this role
- **internal_dns**: Sets `internal_dns_enabled: true` to allow DNS ports
- **edge_ingress**: Sets `edge_ingress_enabled: true` to allow HTTP/HTTPS ports

## License

Proprietary - All Rights Reserved, ExNada Inc.
