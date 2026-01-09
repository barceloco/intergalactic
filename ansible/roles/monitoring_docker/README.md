# monitoring_docker Role

Docker monitoring tools and aliases for container monitoring on Debian-family systems.

## What This Role Does

Installs **ctop** (Container Top) and provides convenient aliases for Docker container monitoring:

- **ctop**: Interactive container monitoring tool (similar to `top` for containers)
- Docker monitoring aliases for common operations

## Requirements

- Debian distribution (tested on Debian trixie/testing)
- Ansible 2.9+
- Root/sudo access (role uses `become: true`)
- **Docker must be installed separately** (this role does not install Docker)
- Network access to GitHub (for binary installation if apt package unavailable)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `monitoring_docker_ctop_install_method` | `"auto"` | Installation method: `"auto"` (try apt first, fallback to binary), `"apt"`, or `"binary"` |
| `monitoring_docker_ctop_version` | `"latest"` | ctop version: `"latest"` (resolve via GitHub API) or specific version (e.g., `"0.7.7"`) |
| `monitoring_docker_aliases_enabled` | `true` | Create `/etc/profile.d/docker-monitoring-aliases.sh` with Docker aliases |
| `monitoring_docker_add_users_to_docker_group` | `[]` | List of users to add to docker group (e.g., `["pi", "deploy"]`) |

### Architecture Mapping

The role automatically maps Ansible architecture to ctop binary architecture:

- `x86_64` → `amd64`
- `aarch64` → `arm64`
- `armv7l` → `armv7`
- `armv6l` → `armv6`

## Installation Methods

### Auto (Default)

The role will:
1. First attempt to install `ctop` from apt (if available)
2. If apt fails, download the official binary from GitHub releases
3. Requires network access to GitHub API (for version resolution) and GitHub releases (for binary download)

### Apt Only

```yaml
monitoring_docker_ctop_install_method: "apt"
```

Only attempts apt installation. Fails if package is not available.

### Binary Only

```yaml
monitoring_docker_ctop_install_method: "binary"
```

Skips apt and directly downloads binary from GitHub releases.

## Version Pinning

For production environments or when network access is restricted, pin a specific version:

```yaml
monitoring_docker_ctop_version: "0.7.7"
```

This avoids GitHub API calls and downloads a specific release directly.

## Aliases Provided

The role creates `/etc/profile.d/docker-monitoring-aliases.sh` with the following aliases:

- `dstats`: `docker stats --no-stream` - One-shot container statistics
- `dtop`: `docker stats` - Continuous container statistics
- `ctop`: `ctop` - Interactive container top
- `dps`: `docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"` - Formatted container list
- `dlogstail`: `docker logs --tail 200 -f` - Tail and follow container logs

## Usage Examples

### Basic Usage

```yaml
- hosts: all
  become: true
  roles:
    - monitoring_docker
```

### Pin Version (Recommended for Production)

```yaml
- hosts: all
  become: true
  roles:
    - role: monitoring_docker
      vars:
        monitoring_docker_ctop_version: "0.7.7"
        monitoring_docker_ctop_install_method: "binary"
```

### Add Users to Docker Group

```yaml
- hosts: all
  become: true
  roles:
    - role: monitoring_docker
      vars:
        monitoring_docker_add_users_to_docker_group:
          - pi
          - deploy
```

**Important**: Users must log out and log back in for docker group membership to take effect.

### Disable Aliases

```yaml
- hosts: all
  become: true
  roles:
    - role: monitoring_docker
      vars:
        monitoring_docker_aliases_enabled: false
```

## Using ctop

After installation, run `ctop` to see an interactive view of all containers:

```bash
ctop
```

Navigation:
- `q`: Quit
- `s`: Stop container
- `r`: Restart container
- `a`: Show all containers (including stopped)
- Arrow keys: Navigate

## Using Docker Monitoring Aliases

After logging in (aliases are sourced from `/etc/profile.d/`):

```bash
dstats          # One-shot container stats
dtop            # Continuous container stats
ctop            # Interactive container top
dps             # Formatted container list
dlogstail <container>  # Tail container logs
```

## Notes

- **Docker must be installed separately** - this role only installs monitoring tools
- `docker stats` is part of Docker CLI and does not need separate installation
- On Debian trixie/testing, ctop is typically installed via binary (apt package may not be available)
- Aliases are available after logging in (they're sourced from `/etc/profile.d/`)
- The role is idempotent: running it multiple times produces no changes (unless packages are updated)
- For production, pin `monitoring_docker_ctop_version` to avoid GitHub API dependency and ensure reproducibility
- Binary installation requires network access to GitHub releases
- Users added to docker group must logout/login for changes to take effect

## Troubleshooting

### ctop Installation Fails

1. **Network access issue**: Ensure the host can reach `api.github.com` and `github.com`
2. **Version resolution fails**: Pin a specific version using `monitoring_docker_ctop_version: "0.7.7"`
3. **Architecture mismatch**: Check that `ansible_facts['architecture']` is supported

### Aliases Not Available

Aliases are sourced from `/etc/profile.d/` - you need to:
- Log out and log back in, OR
- Run `source /etc/profile.d/docker-monitoring-aliases.sh`

### Docker Group Membership Not Working

Users must log out and log back in for group membership changes to take effect. Alternatively, use `newgrp docker` (but this is not persistent).

## Dependencies

None (Docker must be installed separately).

## License

MIT
