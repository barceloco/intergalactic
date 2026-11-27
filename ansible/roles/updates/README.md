# updates Role

Automatic package updates with `unattended-upgrades`, including Debian
security updates.

## What This Role Does

- Installs `unattended-upgrades` and `apt-listchanges`.
- Enables the daily package-list refresh and unattended upgrade
  (`/etc/apt/apt.conf.d/20auto-upgrades`).
- Leaves Debian's packaged `/etc/apt/apt.conf.d/50unattended-upgrades` as
  shipped (it allows Debian and Debian-Security) and adds its own drop-in,
  `52intergalactic-unattended-upgrades`, with the extra origins (Tailscale when
  `enable_tailscale` is true) and the reboot policy. apt merges both files.
- **Gate:** after configuring, it reads `apt-config dump` and fails the play
  unless a Debian-Security origin and every expected extra origin are allowed.

## Repair of the old configuration

Earlier versions of this role used `lineinfile` on `50unattended-upgrades` and
replaced the first line of Debian's `Origins-Pattern` block with
`Unattended-Upgrade::Origins-Pattern { "origin=tailscale"; };`. That orphaned the
Debian entries, so only `origin=tailscale` was allowed, and because origin
matching is case-sensitive (Tailscale's repository says `Origin: Tailscale`) it
matched nothing: **no security updates and no Tailscale updates were installed.**

The role detects that exact line, backs the file up to
`/var/backups/50unattended-upgrades.broken-by-updates-role`, and restores the
packaged copy from `/usr/share/unattended-upgrades/50unattended-upgrades`.

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_unattended_upgrades` | `true` | Enable automatic updates |
| `updates_extra_origins` | `[]` | Extra `Origins-Pattern` entries (case-sensitive, from the repository's Release file) |
| `updates_automatic_reboot` | `false` | Reboot automatically when an update requires it |
| `updates_automatic_reboot_time` | `"04:00"` | When to reboot, if enabled |

Automatic reboots are off by default: a pending reboot shows up as
`/var/run/reboot-required`.

## Verify on a host

```bash
apt-config dump | grep -A6 Origins-Pattern
sudo unattended-upgrade --dry-run -d 2>&1 | grep "Allowed origins"
```

## Tests

`./scripts/run-molecule-tests.sh updates` reproduces the old breakage in a
Debian trixie container, converges the role, checks the gate and idempotency,
and proves with `unattended-upgrade --dry-run` that Debian-Security and
Tailscale are allowed.

## Phase

**Phase 2: Foundation** (`foundation --tags base`).

## License

Proprietary - All Rights Reserved, ExNada Inc.
