# notify

Push notifications from any fleet host through [ntfy](https://ntfy.sh) (open source).

Installs `/usr/local/sbin/fleet-notify`, the one entry point every alert uses:

```bash
fleet-notify [-p priority] [-t tag[,tag]] "<title>" "<message>"
# priority: 1-5 or min, low, default, high, urgent
fleet-notify -p high -t warning "backup stale" "newest vzdump is 40 h old"
```

- The title is prefixed with the hostname: `[merak] backup stale`.
- It never fails its caller. Unconfigured or unreachable ntfy is logged to the
  journal (`journalctl -t fleet-notify`) and the script exits 0.
- The access token goes to curl on stdin, never on the command line.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `notify_enabled` | `false` | per host |
| `notify_ntfy_url` | `https://ntfy.sh` | or a self-hosted server on the tailnet |
| `notify_ntfy_topic` | `""` | **secret**, all_secrets.yml; 16+ random characters |
| `notify_ntfy_token` | `""` | **secret**, optional |
| `notify_default_priority` | `default` | |
| `notify_boot_message` | `false` | sends "<host> booted" once per boot |

The configuration lands in `/etc/fleet-notify.conf` (root, 0600).

On the phone: install the ntfy app and subscribe to the same server and topic.
