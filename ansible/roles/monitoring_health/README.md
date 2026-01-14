# monitoring_health Role

Provides automated health monitoring and alerting for infrastructure services using systemd timers.

## What This Role Does

- Deploys unified health check script
- Creates systemd service and timer for automated health checks
- Configures health check logging
- Monitors: Docker, Tailscale, CoreDNS, Traefik, Backend services

## Requirements

- Debian distribution (tested on Debian trixie/testing)
- Ansible 2.9+
- Root/sudo access (role uses `become: true`)
- Docker installed (for container health checks)
- Health check script available

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `monitoring_health_enabled` | `false` | Enable this role (set to `true` in host_vars) |
| `monitoring_health_interval` | `60` | Health check interval in seconds |
| `monitoring_health_log_dir` | `/var/log/health-monitor` | Directory for health check logs |

## Dependencies

None (but requires Docker and services to be running for meaningful health checks).

## What Gets Created

1. **Health Check Script**: `/usr/local/bin/health-check.sh`
   - Unified health checking for all services
   - Checks Docker, Tailscale, CoreDNS, Traefik, Backends

2. **Systemd Service**: `/etc/systemd/system/health-monitor.service`
   - Runs health check script
   - Logs to systemd journal

3. **Systemd Timer**: `/etc/systemd/system/health-monitor.timer`
   - Runs health checks at configured interval
   - Enabled and started automatically

4. **Log Directory**: `/var/log/health-monitor/`
   - Directory for health check logs (if needed)

## Usage

Enable in host_vars:

```yaml
monitoring_health_enabled: true
monitoring_health_interval: 60  # Check every 60 seconds
```

## Health Checks Performed

- Docker daemon status
- Tailscale connectivity
- CoreDNS container and DNS resolution
- Traefik container and API
- Backend service health (if configured)
- Systemd service status

## Exit Codes

- `0`: All checks passed
- `1`: One or more checks failed

## Logs

Health check results are logged to systemd journal:

```bash
journalctl -u health-monitor
```
