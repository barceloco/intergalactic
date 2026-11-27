# app_homepage Role

[Homepage](https://gethomepage.dev) as the fleet dashboard, at
`https://home.exnada.com` (tailnet only, through Traefik on rigel).

## What it shows

- **Apps:** one tile per route in rigel's `edge_ingress_routes`, with the
  backend host and port and a live status dot (Homepage checks each route's
  health path through rigel's DNS and Traefik, like a browser does).
- **Monitoring:** the Gatus summary (sites up, down, uptime) with a link to
  `status.exnada.com`.
- **Hosts:** `homepage_hosts`, each with its Tailscale address and role.

Tiles are generated from the inventory: a route added on rigel appears after
the next `--tags homepage` deploy.

## How it runs

- Pinned image by digest (`homepage_image_tag`, `homepage_image_digest`).
- As UID 1000 (owner of the image's files), read-only root filesystem, no
  capabilities, `no-new-privileges`. Writable only: tmpfs `/tmp` and
  `/app/.next/cache`. Logs to stdout.
- Configuration in `/opt/homepage/config`, mounted read-only. Every file
  Homepage looks for is provided, so it never tries to write example files.
- No Docker socket (root-equivalent) and no secrets.
- DNS through rigel's CoreDNS (`homepage_dns_server`).
- `HOMEPAGE_ALLOWED_HOSTS`: its public name, the local health check, and
  `vega:3070` / vega's Tailscale address (the Host headers Traefik's backend
  health check sends; without them Homepage answers 400 and Traefik 503).
- Port 3070 (3000 + letter sum of "homepage"), open to rigel only.

The deploy gates on `/api/healthcheck` with Traefik's Host header and on
`/api/services` serving every generated group. A container is recreated when
the configuration changes (hash label).

## Deploy

```bash
./scripts/test-homepage-config.sh                        # local, touches no host
./scripts/run-ansible.sh prod vega production --tags homepage
```

The route is in `host_vars/rigel.yml` (`--tags dns,edge` on rigel) and the
firewall rule in `host_vars/vega.yml` (`foundation --tags security` on vega).

## Test

`scripts/test-homepage-config.sh` renders the configuration from the real
inventory, runs the pinned image with the same hardening, and checks that
every file is accepted, the groups are served, each app's status check
answers, the Gatus widget works, and nothing tries to write.

## Remove

`homepage_enabled: false` (role still in the play) stops the container and
removes `/opt/homepage`.

## License

Proprietary - All Rights Reserved, ExNada Inc.
