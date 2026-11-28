# image_watch Role

A daily check, on vega, of the fleet's pinned container images: Traefik and
CoreDNS (rigel), Gatus and Homepage (vega).

## What it pushes (through fleet-notify / ntfy)

- **Urgent:** a published security advisory affects a pinned version, with
  its severity, summary and link. Go projects (Traefik, CoreDNS, Gatus) are
  matched by GitHub's advisory database for the exact version
  (`/advisories?affects=module@version`); Homepage by evaluating its
  repository's advisory version ranges.
- **Low:** a newer release than the pinned one, with the release link.
- **Low:** a check that failed (once per day per image).

Each finding is pushed once and recorded only after delivery, so a failed
push is retried the next day. State: `/var/lib/image-watch/seen`.

## What it does not do

It never changes anything. To update: change the pin
(`edge_ingress_image_tag`/`_digest`, `internal_dns_image_tag`/`_digest`,
`gatus_image_tag`/`_digest`, `homepage_image_tag`/`_digest`), run the local
image test (`scripts/test-traefik-config.sh`, `scripts/test-coredns-image.sh`,
`scripts/test-gatus-config.sh`, `scripts/test-homepage-config.sh`), and deploy;
the deploys gate and, for routes, roll back.

## Privacy

Only public GitHub API queries leave vega (unauthenticated, about eight a
day). No account, token or repository access. The pins are read at deploy
time from the roles that deploy the images (one source of truth) and written
to `/etc/image-watch.conf`.

## Run it now

```bash
sudo systemctl start image-watch.service
journalctl -t image-watch -n 20
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `image_watch_enabled` | `false` | Install (true) or remove (false) |
| `image_watch_on_calendar` | `*-*-* 09:30:00` | When to check |
| `image_watch_images` | Traefik, CoreDNS, Gatus, Homepage | name, tag, repo, Go module or `-` |

A Go module path includes the major version (`github.com/traefik/traefik/v3`):
update it with a major upgrade.

## Test

`./scripts/run-molecule-tests.sh image_watch` runs the real check against the
live GitHub API with known answers: a vulnerable Traefik 3.0.4 is reported,
CoreDNS 1.15.0 is not, a Homepage range is evaluated both ways, nothing is
pushed twice, and an undelivered push is retried.

## License

Proprietary - All Rights Reserved, ExNada Inc.
