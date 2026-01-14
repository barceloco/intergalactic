# monitoring_base Role

CLI-only monitoring tooling for Debian-family systems (Raspberry Pi OS, Debian, Ubuntu).

## What This Role Does

Installs essential command-line monitoring tools and provides convenient aliases for system monitoring:

- **htop**: Interactive process viewer
- **procps**: Provides `vmstat`, `free`, and other process utilities
- **sysstat**: Provides `iostat`, `sar` (System Activity Reporter) for historical performance data
- **tmux**: Terminal multiplexer (optional, enabled by default)

## Requirements

- Debian distribution (tested on Debian trixie/testing)
- Ansible 2.9+
- Root/sudo access (role uses `become: true`)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `monitoring_base_install_tmux` | `true` | Install tmux terminal multiplexer |
| `monitoring_base_enable_sysstat` | `true` | Enable sysstat data collection (sar, iostat historical data) |
| `monitoring_base_aliases_enabled` | `true` | Create `/etc/profile.d/monitoring-aliases.sh` with CLI aliases |

## Aliases Provided

The role creates `/etc/profile.d/monitoring-aliases.sh` with the following aliases:

- `mem`: `free -h` - Memory usage in human-readable format
- `v1`: `vmstat 1` - Virtual memory statistics updated every second
- `io1`: `iostat -xz 1` - I/O statistics updated every second
- `top10`: Top 10 processes by CPU usage
- `mem10`: Top 10 processes by memory usage
- `dmesgt`: Last 80 lines of kernel messages with timestamps
- `p_cpu`: CPU pressure stall information (kernel 4.20+)
- `p_mem`: Memory pressure stall information (kernel 4.20+)
- `p_io`: I/O pressure stall information (kernel 4.20+)

## Usage Examples

### Basic Usage

```yaml
- hosts: all
  become: true
  roles:
    - monitoring_base
```

### Disable sysstat Collection

```yaml
- hosts: all
  become: true
  roles:
    - role: monitoring_base
      vars:
        monitoring_base_enable_sysstat: false
```

### Disable tmux Installation

```yaml
- hosts: all
  become: true
  roles:
    - role: monitoring_base
      vars:
        monitoring_base_install_tmux: false
```

## Using the Monitoring Tools

### vmstat

View virtual memory statistics:
```bash
vmstat 1        # Update every second
vmstat 5 10     # Update every 5 seconds, 10 times
```

### iostat

View I/O statistics:
```bash
iostat -xz 1    # Extended stats, exclude zero-activity devices, update every second
iostat -x 5     # Extended stats every 5 seconds
```

### sar (System Activity Reporter)

View historical performance data collected by sysstat:
```bash
sar -u          # CPU utilization
sar -r          # Memory utilization
sar -d          # Disk I/O
sar -n DEV      # Network statistics
sar -A          # All statistics
```

Historical data is stored in `/var/log/sysstat/` (typically kept for 7-28 days depending on configuration).

### PSI (Pressure Stall Information)

Linux kernel 4.20+ provides pressure stall information via `/proc/pressure/`:
- **CPU pressure**: Indicates CPU contention
- **Memory pressure**: Indicates memory pressure
- **I/O pressure**: Indicates I/O wait

Lower values are better. Values above 10% indicate resource pressure.

## Notes

- Aliases are available after logging in (they're sourced from `/etc/profile.d/`)
- sysstat collection is controlled via `/etc/default/sysstat` (ENABLED="true"/"false")
- sysstat collection is lightweight and safe for SD-card based systems (default retention is typically 7-28 days)
- PSI files require Linux kernel 4.20+ (available on Debian trixie and later)
- The role is idempotent: running it multiple times produces no changes (unless packages are updated)
- sysstat systemd units (timers/services) are only managed if they exist on the system

## Dependencies

None.

## License

Proprietary - All Rights Reserved, ExNada Inc.
