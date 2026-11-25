# Failover: DNS and reverse proxy on a Pi

**Status: untested until the first drill.** Written before arcturus exists;
the first drill is part of the migration's acceptance criteria.

When arcturus is down (hardware failure, or locked after a reboot while you
cannot unlock it), megrez's CoreDNS and Traefik are gone, and every
`*.exnada.com` name stops resolving. Either Pi alone, vega or rigel, can take
over both:

- **DNS:** CoreDNS serves `exnada.com` on the Pi, every app domain pointing at it.
- **Reverse proxy:** Traefik serves the wildcard certificate. Every app shows
  a "down for maintenance" page, except the key apps you restore on the Pi
  (`failover_apps`).

The Pis are standbys: they hold no GoDaddy credentials and no certificate until
you activate, and lose both again when you deactivate.

## Before you start

- Pick the Pi that is up and patched. Both are equivalent; vega (Pi 5) is the
  stronger one for key apps.
- The Pi must be a **standby**: its host_vars must NOT set `edge_ingress_enabled`
  or `internal_dns_enabled`. The playbook refuses otherwise (today rigel is
  still the live edge, so failover only applies after the move to megrez).
- Optional, faster: a recent copy of megrez's `/opt/traefik/acme.json` on the
  Mac, for when megrez is unreachable (otherwise Traefik requests a new
  certificate, which takes a few minutes and needs GoDaddy to answer).

## Activate

1. **Optional: restore 1 to 2 key apps** on the Pi (decision pending: which
   apps). For each: deploy its app role, restore the latest database dump from
   mpnas, check its `/health` locally. Then list it, e.g.

   ```bash
   -e '{"failover_apps": [{"host": "docgen.exnada.com", "backend": "http://127.0.0.1:8048", "health_path": "/health"}]}'
   ```

2. **Run the failover:**

   ```bash
   ./scripts/run-ansible.sh prod vega failover -e failover_mode=activate
   # if megrez is unreachable and you keep a copy of its certificate store:
   #   -e failover_acme_json_src=/path/on/the/Mac/acme.json
   ```

   It opens 53 and 80/443 to the tailnet in the Pi's firewall, starts the
   maintenance page, CoreDNS and Traefik, and prints the HTTP status of every
   route (503 for the maintenance page, 200 for restored apps).

3. **Note the Pi's Tailscale IP:** `tailscale ip -4` on the Pi, or the
   Tailscale admin console's Machines page.

4. **Switch DNS (by hand, Tailscale admin console):**
   1. https://login.tailscale.com/admin/dns
   2. Nameservers > the custom nameserver restricted to `exnada.com` (split DNS).
   3. Edit: replace megrez's Tailscale IP with the Pi's. Save.

   Clients pick it up within a minute. Check from the Mac:

   ```bash
   dig +short docgen.exnada.com     # the Pi's Tailscale IP
   curl -sI https://docgen.exnada.com | head -1
   ```

## Deactivate (arcturus is back)

1. Unlock arcturus and confirm megrez serves again:
   `curl -sk --resolve docgen.exnada.com:443:<megrez Tailscale IP> https://docgen.exnada.com/ -o /dev/null -w '%{http_code}\n'`
2. **Switch DNS back** (admin console, as in step 4): put megrez's Tailscale IP
   back on the `exnada.com` nameserver.
3. Copy back any data the restored key apps changed while they ran on the Pi
   (database dump on the Pi, restore on dubhe), before deactivating.
4. **Run:**

   ```bash
   ./scripts/run-ansible.sh prod vega failover -e failover_mode=deactivate
   ```

   It stops and removes Traefik, CoreDNS and the maintenance page, deletes
   `/opt/traefik` (GoDaddy credentials, certificate) and `/opt/coredns`, and
   closes 53 and 80/443 again. Stop any key apps you started in step 1 of
   Activate.

## Drill (twice a year)

Run the whole procedure on purpose, with arcturus up, during a quiet hour:

- [ ] Note the date and which Pi; alternate vega and rigel between drills.
- [ ] Activate without `failover_acme_json_src` (certificate from megrez).
- [ ] Switch DNS; from the Mac and a phone: every app domain shows the
      maintenance page, key apps answer.
- [ ] Time it: DNS switch to first working page (target: under 15 minutes).
- [ ] Switch DNS back; deactivate; confirm on the Pi that `/opt/traefik` is
      gone and `nft list ruleset` no longer opens 53 or 443.
- [ ] Record the result and any fix in this runbook (and remove the
      "untested" status after the first successful drill).

## Known gaps

- The DNS switch is manual (admin console); automating it would need a
  Tailscale API key, one more secret.
- CoreDNS binds port 53 on the Pi. If the Pi runs a local resolver on port 53
  (systemd-resolved's stub listens on 127.0.0.53 only, which does not
  conflict), the first drill will show it.
- Media, immich, the file shares and dev do not fail over; their data stays
  safe on mpnas and the USB backup until arcturus is back.
