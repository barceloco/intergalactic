# desktop Role

Installs desktop environment for GUI access (Gen5 workstations only).

## What This Role Does

- Installs desktop environment packages
- Configures display manager
- Sets up GUI utilities

## Requirements

- Debian distribution
- Ansible 2.9+
- Root/sudo access
- Raspberry Pi Gen5 (sufficient hardware)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_desktop` | `false` | Enable desktop environment |

## Dependencies

- Part of Phase 3 (Production)
- Optional, only for workstation hosts

## Phase

**Phase 3: Production** - Desktop environment

## Usage Example

```yaml
# In host_vars/vega.yml (Gen5 workstation)
enable_desktop: true
```

## License

Proprietary - All Rights Reserved, ExNada Inc.
