# common Role

Applies common system configuration and base packages for all hosts.

## What This Role Does

- Installs essential system packages
- Configures system timezone
- Sets up basic system utilities
- Configures system logging
- Applies common sysctl settings

## Requirements

- Debian distribution
- Ansible 2.9+
- Root/sudo access

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `timezone` | `UTC` | System timezone |

## Dependencies

- Part of Phase 2 (Foundation)
- Should run early in foundation phase

## Phase

**Phase 2: Foundation** - Base system configuration

## License

Proprietary - All Rights Reserved, ExNada Inc.
