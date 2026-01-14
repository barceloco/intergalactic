# fail2ban Role

Installs and configures fail2ban for intrusion prevention and security monitoring.

## What This Role Does

- Installs fail2ban package
- Configures SSH jail for failed login attempts
- Sets up permanent ban policy (~10 years)
- Logs all offenders to `/var/log/intergalactic/fail2ban-offenders.log`
- Detects invalid user attempts, wrong SSH keys, and reconnaissance

## Requirements

- Debian distribution
- Ansible 2.9+
- Root/sudo access
- SSH service running

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_fail2ban` | `true` | Enable fail2ban (set to false to disable) |
| `fail2ban_maxretry` | `5` | Failed attempts before ban |
| `fail2ban_bantime_seconds` | `315360000` | Ban duration (~10 years, effectively permanent) |

## Dependencies

- Should run after `ssh_hardening`
- Part of Phase 2 (Foundation)

## Phase

**Phase 2: Foundation** - Security hardening

## What It Detects

- Invalid user attempts (e.g., trying `root`, `admin`, non-existent users)
- Wrong SSH key attempts (valid user, wrong key)
- Port scanning and reconnaissance activity
- All offenders logged for security intelligence

## Why Keep With Key-Only Auth?

- **Defense in depth**: Additional security layer
- **Security intelligence**: See who's probing your systems
- **Misconfiguration protection**: Detects if password auth accidentally re-enabled
- **Industry standard**: Common in hardened production environments

## Usage Example

```yaml
# In group_vars/all.yml (enabled by default)
enable_fail2ban: true
fail2ban_maxretry: 5

# To disable entirely
enable_fail2ban: false
```

## Unban an IP

```bash
fail2ban-client set sshd unbanip <IP>
```

## License

Proprietary - All Rights Reserved, ExNada Inc.
