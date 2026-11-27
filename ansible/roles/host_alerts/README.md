# host_alerts

Tripwires and health checks that push to your phone through `fleet-notify`
(role `notify`, ntfy). Runs on vega and rigel.

**What it is and is not.** These are entry tripwires and hygiene checks. They
tell you, within seconds or minutes, when someone logs in, uses sudo, plants a
key, adds a cron job or a container, or when a disk, container or update
breaks. They are **not tamper-proof**: an attacker with root can stop them.
That silence is what the **dead-man check-in** (Healthchecks.io) makes
visible, and the off-host signals (Tailscale device notifications, Cert
Spotter, GoDaddy and DSM login notifications) are the part no host-level
attacker can suppress. A compromised app container that never logs in and
touches no watched file raises no alert yet.

## Parts

### host-alerts-follow (service)
Follows the journal (`sshd`/`sshd-session`, `sudo`, `login`, `lightdm`, `su`)
and pushes each event. It is **not in the login path**: it can never block or
slow SSH or sudo, and removing it is removing one unit.

| Event | Priority |
|---|---|
| SSH login from outside the tailnet and the LAN | urgent |
| automation user (`ansible`) from an operator source | default, once per 15 min burst |
| automation user from any other source | **urgent** (a stolen automation key) |
| privileged user (`deploy`) from an operator source / elsewhere | high / urgent |
| human user (from `human_users`) | high |
| any other user | urgent |
| `sudo` by anyone but `ansible` and root, with the command (values that look like secrets masked) | high |
| refused `sudo` | high |
| local console, desktop or `su` session | high |

Each push names the user, the source address and the key fingerprint.
Entries are accepted only by journald's trusted fields: `_UID=0` for sshd,
login and the display managers, and the executable (`_EXE`) for the setuid
programs sudo and su, so an unprivileged process cannot forge them with
`logger`. A sudo or su line whose `_EXE` journald could not record (the
process exited first, typical for a refused sudo) is still pushed, marked
"sender unverified"; a line with a different `_EXE` is ignored as a forgery.
**An "automation session" push while you are not deploying is the
indicator to act on.**

### host-alerts-check (timer, every 5 min)
- **Problems**, pushed when seen in two runs in a row and resolved after two
  clean runs: filesystem above `host_alerts_disk_percent`, the Docker daemon
  not answering (urgent; container problems then stay open), a container with
  restart policy `always`/`unless-stopped` not running, reboot required,
  security updates pending longer than `host_alerts_security_update_days`, the
  follower not running (urgent).
- **Events**, pushed once: container restarts (a crash loop at most hourly),
  kernel storage errors (I/O, ext4, mmc, nvme; the SD card has no SMART; the
  first run scans the whole boot), new fail2ban bans.
- **Integrity**: SHA-256 baselines of the security-critical files every run
  (`/etc/ssh/authorized_keys.d`, which is where sshd reads keys on these hosts,
  sshd config, sudoers, passwd/shadow/group, PAM, `ld.so.preload`, nftables,
  the alerting chain itself, `/usr/local/{s,}bin`) and of a second tier hourly
  (systemd units, cron, apt sources and keys, Docker daemon config, fail2ban,
  shell profiles, per host extras such as `/opt/traefik` and `/opt/coredns`).
- **Inventory**: containers (image, privileged, network, mounts), listening
  ports, tailnet peers, enabled units, users with a login shell.
- Changes made while an operator automation session is active, or right after
  a package installation, are labeled so; the label lowers the priority one
  step but never below default for the security-critical set.
- **Dead-man**, first in every run: pings the host's Healthchecks.io URL
  (`/fail` when the follower is down or a push failed in the last 15 min).
  If the pings stop, Healthchecks.io alerts you. Give it an **email**
  integration as well as ntfy, so a broken ntfy channel is still noticed.
- Change alerts list security-relevant lines first and at most 25 lines; the
  full diff is kept in `/var/lib/host-alerts/last-diff.<name>`. A missing
  baseline outside an install is itself a high-priority alert.
- Pushes use `fleet-notify -s`; state is committed only after delivery, so an
  alert lost to a network problem is sent again on the next run. State that
  changes every run lives in `/run`; baselines and alerted problems in
  `/var/lib/host-alerts` are written only when they change (SD card).

### host-alerts-digest (timer, daily)
One low-priority summary: uptime, open problems, pending security updates,
reboot required, SSH logins of the last 24 hours by user and source.

### smartd (optional, `host_alerts_smart: true`)
SMART monitoring with self-tests and temperature limits; warnings go to
`fleet-notify`. On vega only (NVMe and the 6 TB drives).

## Configuration

In host_vars: `host_alerts_enabled`, `host_alerts_smart`,
`host_alerts_extra_paths`. In `all_secrets.yml` (never in host_vars):

```yaml
host_alerts_operator_sources: ["100.x.y.z"]   # your Mac's Tailscale IP
host_alerts_healthchecks_urls:
  rigel: "https://hc-ping.com/<uuid>"
  vega: "https://hc-ping.com/<uuid>"
```

The role refuses to run without `notify_enabled`, the operator sources, and a
dead-man URL (unless `host_alerts_require_deadman: false`). See
`defaults/main.yml` for every variable.

## Deploy and revert

```bash
./scripts/run-ansible.sh prod rigel production --tags notify,host_alerts
```

Revert: set `host_alerts_enabled: false` (keep the role in the play) and run
the same command; everything the role installed is removed (smartd.conf is
restored only if this role wrote it).

## Tests

`./scripts/run-molecule-tests.sh host_alerts` (Debian trixie with systemd):
converge, idempotence, each login class, a burst of 50 automation logins
collapsed into one push, a real sshd key login, sudo, a follower restart
without replay, a forced disk problem, a planted key in
`/etc/ssh/authorized_keys.d`, the digest, then disable (everything removed)
and enable again. The scripts are shellchecked by
`./scripts/test-shell-templates.sh`.
