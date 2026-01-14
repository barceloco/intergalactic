# ssh_hardening Role

Applies SSH server hardening configuration for enhanced security.

## What This Role Does

- Configures SSH daemon with security best practices
- Sets SSH allowlist for authorized users
- Disables root login
- Configures SSH port
- Applies recommended cipher suites and key exchange algorithms
- Sets up SSH session limits and timeout

## Requirements

- Debian distribution
- Ansible 2.9+
- Root/sudo access
- SSH service installed (openssh-server)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_port` | `22` | SSH port number |
| `ssh_allow_users` | (auto) | Whitelist of allowed SSH users (auto-generated from automation + human users + deploy) |

## Dependencies

- Should run after `common_bootstrap` (which creates users)
- Part of Phase 2 (Foundation)

## Phase

**Phase 2: Foundation** - Applied during foundation phase

## What Gets Configured

- `/etc/ssh/sshd_config.d/50-intergalactic-hardening.conf`:
  - `PermitRootLogin no`
  - `AllowUsers <whitelist>`
  - Secure cipher suites
  - Key exchange algorithms
  - Session timeouts

## Usage Example

```yaml
# Configuration is automatic
# ssh_allow_users is generated from:
# - automation_user (ansible)
# - human_users (from all_secrets.yml)
# - deploy user (if enable_docker_deploy: true)
```

## License

Proprietary - All Rights Reserved, ExNada Inc.
