# docker_host Role

Installs and configures Docker Engine for container runtime.

## What This Role Does

- Installs Docker Engine from official Docker repository
- Configures Docker service to start on boot
- Optionally adds automation user to docker group
- Sets up Docker for host network mode services

## Requirements

- Debian distribution
- Ansible 2.9+
- Root/sudo access

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_docker` | `true` | Enable Docker installation |
| `docker_add_automation_user` | `true` | Add automation user to docker group |

## Dependencies

- Part of Phase 2 (Foundation)
- Must run before `docker_deploy` and any Docker service roles

## Phase

**Phase 2: Foundation** - Infrastructure setup

## What Gets Installed

- Docker Engine (latest stable)
- Docker CLI
- containerd
- Docker Compose plugin

## Usage Example

```yaml
# In group_vars/all.yml
enable_docker: true
docker_add_automation_user: true
```

## License

Proprietary - All Rights Reserved, ExNada Inc.
