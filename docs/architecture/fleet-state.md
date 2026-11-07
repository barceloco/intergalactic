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
| rigel | Raspberry Pi 4, 128 GB SD card | Dev app server, edge (Traefik, CoreDNS), observability | Running |
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
| monitor.exnada.com | rigel:3000 | Grafana (with Prometheus, Alertmanager, blackbox) | `/srv/observability` | n/a | `observability` |
| immich.exnada.com | mpnas:2283 | immich | not managed here | n/a | route only |

Edge services on rigel are systemd-managed containers: `traefik.service`
(`/opt/traefik`, ports 80, 443, 8082 metrics) and `coredns.service`
(`/opt/coredns`, port 53). Both hosts run `prometheus-node-exporter` on 9100.

## Other Services

| Host | Service | Managed by |
|---|---|---|
| vega | Samba (`smbd`, `nmbd`) on 139/445 | `samba` role |
| vega | Desktop (`lightdm`), CUPS | `desktop` role |
| vega | `samba-ad-dc` and `winbind` units enabled (AD DC is not serving) | Package defaults, not intended |
| vega | OpenClaw workspace in `/home/armand/.openclaw` with a grant-watch checkout | Not managed here |
| vega | Unidentified listeners on localhost ports 18789 and 18792 | Not managed here |

## Known Drift

These differ from what the repo intends. Each is a follow-up, not yet fixed:

- **vega: aispector data ports are published on all interfaces.** Postgres
  (5432), Redis (6379), and MinIO (9000, 9001) bind `0.0.0.0`. Docker-published
  ports bypass the nftables input chain, so they are reachable beyond
  localhost. Bind them to `127.0.0.1` in the aispector compose files.
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
  still in `docker_deploy_git_repos`, and ports 8000, 5432, 6379, 9000, 9001
  stay open in `docker_deploy_tcp_ports`.
- **rigel: `enable_samba: true` has no effect.** rigel's production playbook does
  not include the `samba` role and no Samba service runs.
- **Both: unattended-upgrades is enabled but not applying security updates.**
  On 2026-11-04, rigel had 61 and vega 141 pending packages from Debian security.
