# Fleet State (As Deployed)

What the fleet actually runs, observed on the hosts on 2026-11-04 with the
read-only audit. Where this page and another doc disagree, this page reflects
the hosts. Re-verify at any time:

```bash
./scripts/run-ansible.sh prod vega audit
./scripts/run-ansible.sh prod rigel audit
```

## Hosts

| Host | Hardware | Role | Status |
|---|---|---|---|
| vega | Raspberry Pi 5, 256 GB NVMe | Production app server | Running |
| rigel | Raspberry Pi 4, 128 GB SD card | Dev app server, edge (Traefik, CoreDNS) | Running |
| mpnas | NAS, not Ansible-managed | immich backend behind rigel's Traefik | Not managed here |
| alpheratz, deneb | Pi 3, Pi 1 | Foundation-only, minimal | Offline since early 2026 |
| saiph, g1, ngc604 | Pi 1 | Inventory placeholders, no playbooks | Never deployed |

Both running hosts are on Debian 13 (trixie). On 2026-11-06 both were fully upgraded and rebooted onto kernel 6.18.60; every container came back (rigel 8, vega 9) and all routes returned 200.

## Storage

Neither host uses the 3-partition layout described in the README. Both have a
boot partition and one root partition, with no separate `/home`. **No internal
disk is encrypted.**

| Host | Device | Partitions | Encrypted |
|---|---|---|---|
| vega | NVMe 238.5 GB | `p1` 512 MB vfat `/boot/firmware`, `p2` 238 GB ext4 `/` | No |
| rigel | SD 119.4 GB | `p1` 512 MB vfat `/boot/firmware`, `p2` 118.9 GB ext4 `/` | No |

- **Docker data-root** is `/home/deploy/docker` on both hosts, which is on the
  root filesystem.
- **rigel** bind-mounts `/home/deploy/srv` to `/srv` and `/home/deploy/logs/apps`
  to `/var/log/apps` (the `docker_deploy` role). Both live on the root filesystem.
- **vega** has a real `/srv` directory and no bind mounts. It runs only the
  `git_ssh` part of `docker_deploy`.
- **External drives (vega only):** two WD 6 TB USB drives, each a single LUKS
  partition, mounted as `/crypt/WDD6T` and `/crypt/WDE6T`. They are unlocked by
  hand, are not in `crypttab`, and do not survive a reboot. Keys are not in this
  repo.

## Served Applications

Every app is deployed by an `app_*` role from a git checkout under `/srv`, and
restarts with Docker (`restart: unless-stopped`).

| Route | Host:port | App | Checkout | Branch | Role |
|---|---|---|---|---|---|
| aispector.exnada.com | vega:8000 | aispector (API, Celery worker and beat, Postgres, Redis, MinIO) | `/srv/aispector` | main | `app_aispector` |
| callosal.exnada.com | vega:8001 | callosal (`callosal-serve`, started via `make`, no compose project) | `/srv/callosal` | main | `app_callosal` |
| docgen.exnada.com | vega:8048 | docgen + Postgres (brand from `/srv/docgen-exnada`) | `/srv/docgen` | main | `app_docgen` |
| demo.exnada.com | rigel:8001 | callosal (`callosal-serve`) | `/srv/callosal` | dev | `app_callosal` |
| csa.exnada.com | rigel:8023 | csa | `/srv/csa` | main | `app_csa` |
| immich.exnada.com | mpnas:2283 | immich | not managed here | n/a | route only |

Edge services on rigel are systemd-managed containers: `traefik.service`
(`/opt/traefik`, ports 80, 443; Traefik 3.7.20, pinned by digest) and
`coredns.service` (`/opt/coredns`, port 53; CoreDNS 1.15.0, pinned by digest).
Neither restarts when a route is added (2026-11-27): Traefik reloads
`/opt/traefik/dynamic/dynamic.yml` on SIGHUP and the deploy gates every route
(`scripts/verify-edge-gate.sh`); CoreDNS's reload plugin re-reads the Corefile
within 10 s. Both restart once only when their image, compose file or unit
changes, with the image pulled first.

## Other Services

| Host | Service | Managed by |
|---|---|---|
| vega | Samba (`smbd`, `nmbd`) on 139/445 | `samba` role |
| vega | Desktop (`lightdm`), CUPS | `desktop` role |
| vega | `samba-ad-dc` and `winbind` units enabled (AD DC is not serving) | Package defaults, not intended |
| vega | OpenClaw workspace in `/home/armand/.openclaw` with a grant-watch checkout | Not managed here |
| vega | Unidentified listeners on localhost ports 18789 and 18792 | Not managed here |
| vega, rigel | Alerts: `fleet-notify` (ntfy), `host-alerts-follow` (logins, sudo), `host-alerts-check` timer (health, integrity, inventory), daily digest; smartd on vega. Deployed 2026-11-27 | `notify`, `host_alerts` roles |
| vega | Gatus uptime monitor (`/opt/gatus`, port 8148 from rigel only), status page `status.exnada.com`. Deployed 2026-11-27 | `app_gatus` role |
| vega | Daily image check (`image-watch.timer`, 09:30): urgent push for a published advisory affecting a pinned Traefik, CoreDNS, Gatus or Homepage version, low push for a new release. Deployed 2026-11-27 | `image_watch` role |
| vega | Homepage dashboard (`/opt/homepage`, port 3070 from rigel only) at `home.exnada.com`, tiles generated from rigel's routes. Deployed 2026-11-27 | `app_homepage` role |

## Known Drift

These differ from what the repo intends. Each is a follow-up, not yet fixed:

- **Both: the dead-man check-in is not active yet.** host_alerts was deployed
  on 2026-11-27 with `-e host_alerts_require_deadman=false` because the
  Healthchecks.io URLs did not exist yet. Add `host_alerts_healthchecks_urls`
  to all_secrets.yml and rerun `production --tags notify,host_alerts` on both.
- **rigel: Docker data-root mode.** `docker_host` and `docker_deploy` used to
  set `/home/deploy/docker` to 0750 root:docker, which Docker reset to 0710
  root:root on every start. Both roles now use 0710 root:root (2026-11-27).
- **Both: `common` sysctl hardening fixed and applied (2026-11-27).** The old
  role wrote `/etc/sysctl.conf` (not read at boot on trixie) with strict
  `rp_filter=1`, which would drop traffic to each host's wlan0 address (both
  are dual-homed on the LAN). Now `/etc/sysctl.d/60-intergalactic-hardening.conf`:
  loose `rp_filter=2` and no ICMP redirects on every interface; old lines
  removed. Verified on both: all interfaces, both LAN addresses, routes, DNS,
  Samba, and a boot-time `systemd-sysctl` rerun. No `pi` user exists.
- **Both: failed units at boot (harmless, unused packages).** `openipmi`
  fails on both hosts (no IPMI hardware); `smartmontools` fails on rigel (no
  SMART-capable disk on the SD card). Both rebooted on 2026-11-27 after the
  package upgrade; every container and route came back.

- **vega: aispector data ports are published on all interfaces.** Postgres
  (5432), Redis (6379), and MinIO (9000, 9001) bind `0.0.0.0`. Since the
  allow-list firewall (2026-11-19) they are dropped in the forward chain for
  every off-host source; only other containers on vega can still reach them.
  Bind them to `127.0.0.1` in the aispector compose files anyway.
- **vega: aispector API, worker, and beat report `unhealthy`.** They were up
  for 4 months with a failing health check and stay unhealthy after a reboot,
  although aispector.exnada.com/health returns 200 through Traefik.
- **Both: fail2ban is not running.** Its custom `intergalactic-log` action had
  an unescaped `%s`, so fail2ban refused its whole config. Fixed in the
  `fail2ban` role (with a `fail2ban-client -t` gate); not yet deployed.
- **Both: `openipmi` fails at boot** (no IPMI hardware on a Pi); rigel's
  `smartmontools` also fails (no SMART-capable disk on an SD card). Harmless noise.
- **rigel: leftover aispector.** aispector was removed from rigel on 2026-07-05,
  but `/srv/aispector` (dev, last commit 2026-01-14) remains, `aispector` is
  still in `docker_deploy_git_repos`. (Its ports 8000, 5432, 6379, 9000 and
  9001 were open to the whole LAN via `docker_deploy_tcp_ports`; the allow-list
  firewall retires that variable.)
- **rigel: Samba was configured but never deployed** (`enable_samba: true`, but
  the `samba` role was missing from rigel-production.yml). Added on 2026-11-19.
- **Both: unattended-upgrades was not applying security updates (fixed and deployed 2026-11-27).**
  On 2026-11-04, rigel had 61 and vega 141 pending packages from Debian security.
  Cause (found 2026-11-27): the `updates` role's `lineinfile` replaced the first
  line of Debian's `Origins-Pattern` block, leaving only `origin=tailscale`
  allowed, which (case-sensitive; the repo says `Origin: Tailscale`) matched
  nothing. Fixed in the role (packaged file restored, drop-in, `apt-config`
  gate, molecule test). Deployed to both on 2026-11-27 (`foundation --tags
  updates`) after applying the backlog with `upgrade -e os_upgrade_apply=true`;
  `unattended-upgrade --dry-run` now allows Debian-Security and Tailscale.

## Planned Work

- **Dead-man check-in (backlog, deferred 2026-11-27).** Create Healthchecks.io
  checks for rigel and vega (period 5 min, grace 10 min, email plus ntfy), add
  `host_alerts_healthchecks_urls` to all_secrets.yml, and run
  `production --tags notify,host_alerts` on both. Until then a full production
  run needs `-e host_alerts_require_deadman=false`.
