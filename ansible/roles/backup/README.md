# backup Role

Provides automated backup and restore capabilities for critical configuration files and data.

## What This Role Does

- Deploys backup and restore scripts
- Creates systemd service and timer for automated backups
- Backs up: CoreDNS config, Traefik config, systemd services
- Compresses and retains backups with configurable retention

## Requirements

- Debian distribution (tested on Debian trixie/testing)
- Ansible 2.9+
- Root/sudo access (role uses `become: true`)
- tar and gzip available

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `backup_enabled` | `false` | Enable this role (set to `true` in host_vars) |
| `backup_dir` | `/opt/backups` | Directory for backup storage |
| `backup_interval_hours` | `24` | Backup interval in hours |
| `backup_retention_days` | `7` | Number of days to retain backups |

## Dependencies

None.

## What Gets Created

1. **Backup Script**: `/usr/local/bin/backup-configs.sh`
   - Backs up CoreDNS, Traefik, systemd configurations
   - Creates compressed tar.gz archives
   - Automatic cleanup of old backups

2. **Restore Script**: `/usr/local/bin/restore-configs.sh`
   - Restores configurations from backup
   - Restarts services after restore

3. **Systemd Service**: `/etc/systemd/system/backup.service`
   - Runs backup script

4. **Systemd Timer**: `/etc/systemd/system/backup.timer`
   - Runs backups at configured interval
   - Enabled and started automatically

5. **Backup Directory**: `/opt/backups/`
   - Stores backup archives

## Usage

Enable in host_vars:

```yaml
backup_enabled: true
backup_interval_hours: 24  # Daily backups
backup_retention_days: 7  # Keep 7 days of backups
```

## Manual Backup

```bash
/usr/local/bin/backup-configs.sh
```

## Manual Restore

```bash
# List available backups
ls -lh /opt/backups/

# Restore from specific backup
/usr/local/bin/restore-configs.sh /opt/backups/20240112-120000.tar.gz

# Restore from most recent backup
/usr/local/bin/restore-configs.sh
```

## What Gets Backed Up

- CoreDNS configuration (`/opt/coredns/`)
- Traefik configuration (`/opt/traefik/traefik.yml`, `dynamic.yml`)
- Systemd service files (`/etc/systemd/system/coredns.service`, `traefik.service`)

**Note**: `acme.json` (certificate storage) is NOT backed up by default for security reasons. Handle separately if needed.

## Backup Format

Backups are stored as compressed tar.gz files:
- Format: `YYYYMMDD-HHMMSS.tar.gz`
- Location: `/opt/backups/`
- Contains: All configuration files in timestamped directory

## Retention

Old backups are automatically deleted based on `backup_retention_days` setting.
