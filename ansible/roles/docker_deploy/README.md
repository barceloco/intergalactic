# docker_deploy Role

Sets up a dedicated `deploy` user for Docker container deployment with SSH access, directory structure, bind mounts, and optional Docker daemon configuration.

## What This Role Does

- Creates `deploy` user with SSH access (using same keys as `armand` user)
- Configures directory structure (`/home/deploy/docker`, `/home/deploy/srv`, `/home/deploy/logs/apps`)
- Sets up bind mounts (`/srv` → `/home/deploy/srv`, `/var/log/apps` → `/home/deploy/logs/apps`)
- Installs git
- Configures passwordless sudo for `deploy` user
- Optionally configures Docker daemon DNS servers
- Optionally sets environment variables for `deploy` user
- Integrates with firewall (exposes `docker_deploy_tcp_ports`)

## Requirements

- Debian distribution (tested on Debian trixie/testing)
- Ansible 2.9+
- Root/sudo access (role uses `become: true`)
- `armand` user must exist in `human_users` with SSH keys configured
- Docker must be installed (via `docker_host` role)
- `firewall_nftables` role should run after this role to pick up `docker_deploy_tcp_ports`

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_docker_deploy` | `false` | Enable this role (set to `true` in host_vars) |
| `docker_deploy_tcp_ports` | `[]` | List of TCP ports to expose via firewall (e.g., `[8000, 5432, 6379]`) |
| `docker_deploy_dns_servers` | `[]` | Optional: List of DNS servers for Docker daemon (e.g., `["8.8.8.8", "8.8.4.4"]`) |
| `docker_deploy_env_vars` | `{}` | Optional: Dict of environment variables for deploy user (e.g., `{"API_KEY": "value"}`) |

## Dependencies

- **docker_host**: Docker must be installed before this role runs
- **firewall_nftables**: Should run after this role to pick up `docker_deploy_tcp_ports`

## Directory Structure Created

- `/home/deploy/docker/` - Docker data-root (711 permissions, owned by deploy)
- `/home/deploy/srv/` - Service data (755 permissions, owned by deploy)
- `/home/deploy/logs/apps/` - Application logs (755 permissions, owned by deploy)

## Bind Mounts Configured

- `/srv` → `/home/deploy/srv` (service data accessible at standard location)
- `/var/log/apps` → `/home/deploy/logs/apps` (application logs at standard location)

## Usage Examples

### Basic Usage

```yaml
# In host_vars/rigel.yml
enable_docker_deploy: true
docker_deploy_tcp_ports:
  - 8000   # API
  - 5432   # PostgreSQL
  - 6379   # Redis
```

### With Docker DNS Configuration

```yaml
enable_docker_deploy: true
docker_deploy_tcp_ports:
  - 8000
docker_deploy_dns_servers:
  - 8.8.8.8
  - 8.8.4.4
```

### With Environment Variables

```yaml
enable_docker_deploy: true
docker_deploy_env_vars:
  API_KEY: "your-api-key"
  DATABASE_URL: "postgresql://localhost:5432/mydb"
```

## Prerequisites

The `armand` user must be configured in `all_secrets.yml`:

```yaml
human_users:
  - name: armand
    authorized_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... armand@laptop"
```

The role will copy these SSH keys to the `deploy` user.

## What Gets Created

1. **User Account**: `deploy` user with:
   - Shell: `/bin/bash`
   - Groups: `docker`, `sudo`
   - Home directory: `/home/deploy`

2. **SSH Access**: SSH keys from `armand` user copied to `/etc/ssh/authorized_keys.d/deploy`

3. **Sudo Configuration**: `/etc/sudoers.d/90-deploy` with passwordless sudo

4. **Directory Structure**: All under `/home/deploy/`:
   - `docker/` - Docker data-root
   - `srv/` - Service data
   - `logs/apps/` - Application logs

5. **Bind Mounts**: Configured in `/etc/fstab`:
   - `/srv` → `/home/deploy/srv`
   - `/var/log/apps` → `/home/deploy/logs/apps`

6. **Docker Configuration** (if `docker_deploy_dns_servers` specified):
   - Updates `/etc/docker/daemon.json` with DNS servers
   - Restarts Docker daemon

7. **Environment Variables** (if `docker_deploy_env_vars` specified):
   - Added to `/home/deploy/.bashrc`

## Firewall Integration

The role sets `docker_deploy_tcp_ports` fact which is automatically merged into `firewall_allow_tcp_ports` by the `firewall_nftables` role. Ensure `firewall_nftables` runs after `docker_deploy`.

## Security Considerations

- **SSH Keys**: Copied from `armand` user - ensure `armand` has secure keys
- **Sudo Access**: `deploy` user has passwordless sudo - treat as privileged user
- **Docker Group**: `deploy` user is in `docker` group (root-equivalent access)
- **Directory Permissions**: Docker data-root uses 711 permissions (required by Docker)

## Troubleshooting

### Deploy User Cannot SSH In

1. **Check SSH keys are configured**:
   ```bash
   sudo cat /etc/ssh/authorized_keys.d/deploy
   ```

2. **Check SSH service is running**:
   ```bash
   sudo systemctl status ssh
   ```

3. **Check SSH configuration**:
   ```bash
   sudo grep AuthorizedKeysFile /etc/ssh/sshd_config.d/*
   ```

4. **Verify armand user has keys in secrets**:
   - Check `all_secrets.yml` has `armand` in `human_users` with `authorized_keys`

### Sudo Not Working

1. **Check sudoers file**:
   ```bash
   sudo visudo -c -f /etc/sudoers.d/90-deploy
   ```

2. **Test sudo access**:
   ```bash
   sudo -u deploy sudo whoami
   ```

### Docker Data-Root Not Working

1. **Check directory exists**:
   ```bash
   ls -la /home/deploy/docker
   ```

2. **Check permissions** (must be 711):
   ```bash
   stat -c "%a %n" /home/deploy/docker
   ```

3. **Check Docker daemon.json**:
   ```bash
   sudo cat /etc/docker/daemon.json
   ```

4. **Check Docker is using custom data-root**:
   ```bash
   docker info | grep "Docker Root Dir"
   ```

### Bind Mounts Not Working

1. **Check mount points**:
   ```bash
   findmnt /srv
   findmnt /var/log/apps
   ```

2. **Check /etc/fstab**:
   ```bash
   grep -E "(srv|var/log/apps)" /etc/fstab
   ```

3. **Manually mount to test**:
   ```bash
   sudo mount /srv
   sudo mount /var/log/apps
   ```

## Notes

- The role is idempotent: running it multiple times produces no changes
- SSH keys are copied from `armand` user - changes to `armand` keys require re-running the role
- Docker daemon DNS configuration merges with existing `/etc/docker/daemon.json`
- Environment variables are added to `.bashrc` - users must log out/in or source the file
- Bind mounts are only created if not already mounted
- The role validates that `armand` user exists and has SSH keys before proceeding

## License

Proprietary - All Rights Reserved, ExNada Inc.
