# updates Role

Configures automatic security updates and system update policies.

## What This Role Does

- Installs unattended-upgrades package
- Configures automatic security updates
- Sets up update notifications
- Configures update schedule

## Requirements

- Debian distribution
- Ansible 2.9+
- Root/sudo access

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_unattended_upgrades` | `true` | Enable automatic security updates |

## Dependencies

- Part of Phase 2 (Foundation)
- Independent role

## Phase

**Phase 2: Foundation** - System maintenance

## What Gets Configured

- Automatic security updates enabled
- Daily update checks
- Automatic reboot (if required, at configured time)

## License

Proprietary - All Rights Reserved, ExNada Inc.
