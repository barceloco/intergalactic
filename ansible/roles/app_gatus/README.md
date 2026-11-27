# app_gatus

One [Gatus](https://github.com/TwiN/gatus) instance (open source) on vega that
watches the fleet the way clients see it, pushes alerts to ntfy and serves a
status page at `https://status.exnada.com` (tailnet only, through Traefik).

## What it checks

Generated, so nothing has to be kept in sync by hand:

- **Every route** in the edge host's (`rigel`) `edge_ingress_routes`:
  HTTPS to the route's `health_path` (default `/`) through rigel's CoreDNS and
  Traefik: connection made, status not 404 (Traefik's answer when no router
  matches, so the checked path itself must not answer 404) and below 500,
  certificate valid for more than 10 days. A new route is monitored after the next
  `vega production --tags gatus` run (the configuration is rendered there).
- **Internal DNS** (`gatus_internal_dns_checks`): rigel's CoreDNS answers the
  expected addresses.
- **Public DNS** (`gatus_public_dns_checks`): NS, MX and A records of
  exnada.com at a public resolver match the expected providers, so a DNS
  hijack is noticed.

Alerts after 3 consecutive failures (2 for public DNS), "resolved" after 2
successes. On vega it keeps working when rigel dies: then every route and
internal DNS check fails at once, so expect a burst of alerts (and of
"resolved" messages) for one outage of rigel.

## Security

- Root-owned under `/opt/gatus`; the ntfy topic is in `gatus.env` (0600,
  read by Docker only), never in a file the `deploy` user can read.
- Image pinned by version and digest; container runs as 65534, read-only,
  all capabilities dropped, no-new-privileges, no Docker socket.
- Published on 8148, but vega's firewall admits that port only from rigel
  (Traefik). The status page is readable by every tailnet device that may use
  rigel's 443 (until Tailscale ACLs exist).

## Variables

See `defaults/main.yml`. Required in host_vars: `gatus_enabled`,
`gatus_image_tag`, `gatus_image_digest`; in all_secrets.yml: the notify role's
`notify_ntfy_topic`.

## Deploy and revert

```bash
./scripts/run-ansible.sh prod vega production --tags gatus
```

The status route is in rigel's `edge_ingress_routes`, the firewall rule in
vega's `firewall_rules` (applied with `foundation --tags security`). Revert:
`gatus_enabled: false` and rerun; the container and `/opt/gatus` are removed.

## Tests

`./scripts/test-gatus-config.sh` renders the configuration from the real
inventory and starts the pinned image locally against it.
