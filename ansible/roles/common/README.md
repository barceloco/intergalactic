# common Role

Base system configuration for every host (foundation phase, tag `base`).

## What This Role Does

- Installs base packages (`bind9-dnsutils`, `chrony`, `rsync`, `acl`, ...).
- Keeps `chrony` enabled for time sync.
- Enforces `authorized_keys` for the automation user and human users.
- Locks the default `pi` user if it exists (`disable_default_pi_user`).
- Network sysctl hardening (`tasks/sysctl.yml`), written to
  `/etc/sysctl.d/60-intergalactic-hardening.conf`:
  - `rp_filter = 2` (loose) on all interfaces
  - ICMP redirects neither accepted nor sent, on all interfaces
  - `tcp_syncookies = 1`
- Sets the hostname when `hostname` is defined.

## Why loose rp_filter

The Pis are on the LAN twice (eth0 and wlan0 in the same subnet, eth0
preferred). Strict mode (1) drops packets addressed to the wlan0 address,
because the reply route points at eth0; rigel's foundation inventory address is
its wlan0 address. Loose mode (2) still drops packets whose source has no route
at all, and the nftables allow-list already ties each source to its interface.

## Why /etc/sysctl.d

Debian 13 no longer reads `/etc/sysctl.conf` at boot. Earlier versions of this
role wrote there, so the values were lost at every reboot. The role removes
those old lines, because `sysctl --system` still reads that file, last, and
would bring strict `rp_filter` back. The `*` keys also cover interfaces that
appear later (systemd-sysctl applies them when udev adds an interface).

After applying, a gate reads the live values of every interface and fails the
play if any differs from the file.

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `common_sysctl_file` | `/etc/sysctl.d/60-intergalactic-hardening.conf` | Hardening file |
| `common_rp_filter` | `2` | Reverse-path filter mode |
| `disable_default_pi_user` | (from group_vars) | Lock `pi` if present |

## Tests

`./scripts/run-molecule-tests.sh common` reproduces the old state (strict
`rp_filter` lines in `/etc/sysctl.conf`, redirects on) in a Debian 13
container, converges the sysctl tasks, checks idempotency, reloads
`/etc/sysctl.conf`, and checks every interface.

## Phase

**Phase 2: Foundation** (`foundation --tags base`).

## License

Proprietary - All Rights Reserved, ExNada Inc.
