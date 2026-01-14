# samba Role

Installs and configures Samba file sharing service.

## What This Role Does

- Installs Samba server packages
- Configures Samba shares
- Sets up Samba users with passwords
- Configures firewall for Samba ports (if enabled)

## Requirements

- Debian distribution
- Ansible 2.9+
- Root/sudo access

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_samba` | `false` | Enable Samba (set per-host) |

## Dependencies

- Part of Phase 3 (Production)
- Optional service role

## Phase

**Phase 3: Production** - File sharing service

## SMB Protocol Limitations

**Important**: SMB/NetBIOS names are limited to 15 characters. FQDNs like `host.domain.com` will not work for SMB access. Use short hostnames or IP addresses.

## Usage Example

```yaml
# In host_vars/vega.yml
enable_samba: true
```

## License

Proprietary - All Rights Reserved, ExNada Inc.
