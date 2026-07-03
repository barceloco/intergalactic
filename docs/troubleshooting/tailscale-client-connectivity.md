# Tailscale Client Connectivity Troubleshooting

This covers connectivity problems on the **operator's own machine** (e.g. a
laptop running `ansible`/`ssh`/`curl` against the fleet), not the Pi fleet
hosts themselves. If `tailscale ping` to a fleet host works but real traffic
(SSH, HTTPS) doesn't, start here.

## Common Issues

### Issue: SSH/HTTPS to fleet hosts times out, but `tailscale ping` succeeds

**Symptoms**:
- `ssh <host>` or `curl https://<service>.exnada.com` hangs and times out
  (not a fast refusal, a full connect timeout).
- `tailscale ping <host>` succeeds, but reports `via DERP(...)` and
  `direct connection not established` (should normally go direct on a LAN
  or via a healthy P2P path).
- `dig <host>.exnada.com` may also time out (`no servers could be reached`)
  if MagicDNS (`100.100.100.100`) is affected the same way.
- `tailscale status` / `tailscale netcheck` / `tailscale ping` print:
  `Warning: client version "X" != tailscaled server version "Y"`.

**Root cause (confirmed on 2026-07-02)**: a second, unrelated full-tunnel VPN
is active on the machine at the same time as Tailscale (e.g. a university or
corporate VPN client). Disconnecting the other VPN restored direct
connectivity immediately, which confirmed the conflict. Details from the
occurrence on a MacBook:

- `netstat -rn -f inet` showed a second `utun` interface (`utun10`) holding
  the **default route** (`0.0.0.0/0`, flag `g`), fronting a long list of
  Apple/Google/Akamai/Fastly destinations, alongside Tailscale's own `utun9`
  which correctly had the more-specific `100.64/10` route.
- Routing table priority should favor Tailscale's specific `/10` route for
  tailnet destinations regardless of the other VPN's default route, but many
  corporate/university VPN clients additionally install a system packet
  filter (`pf`) that drops traffic on interfaces/tunnels it doesn't
  recognize, independent of the routing table. That explains why UDP-based
  Tailscale control traffic and DERP-relayed pings (which look like ordinary
  outbound HTTPS to the relay) got through, while direct TCP flows over the
  Tailscale tunnel did not.
- The persistent client/daemon version mismatch is a second, related smell:
  quitting and reopening the Tailscale menu-bar app on macOS does **not**
  necessarily restart the actual background `tailscaled`/network-extension
  process; it just reconnects the UI to whatever daemon is already running.
  If that daemon is stuck or stale, an app-level restart alone won't clear
  the mismatch or the underlying connectivity problem.

**Diagnosis**:
```bash
# Version mismatch is the first tell
tailscale status
tailscale version

# Confirm UDP/DERP control-plane works while suspecting TCP data-plane doesn't
tailscale netcheck
tailscale ping -c 2 <hostname>          # look for "via DERP" + "direct connection not established"

# Look for a second VPN tunnel and who owns the default route
ifconfig | grep -B2 utun
netstat -rn -f inet | grep -iE "^default|100\.|utun"

# Confirm it's not just this one host: try both hostname and raw Tailscale IP
ssh -o ConnectTimeout=8 <hostname> "echo ok"
ssh -o ConnectTimeout=8 <tailscale-ip> "echo ok"

# Rule out DNS specifically vs. general transport failure
dig +short <host>.exnada.com
```

**Solutions** (in order of least to most disruptive). Step 1 is the confirmed
fix for the case above:
1. **Disconnect the other VPN and retest.** Fastest thing to try; if SSH/HTTPS
   start working immediately after, that confirms the conflict.
2. **Configure split-tunnel/exclude routes** on the other VPN client (if it
   supports excluding `100.64.0.0/10` and `100.100.100.100` from its tunnel),
   so both VPNs can stay active simultaneously.
3. **Fully restart the Tailscale daemon, not just the app.** On macOS this
   generally means quitting Tailscale, confirming no `tailscaled` /
   `IPNExtension` process is still running (`ps aux | grep -i tailscale`),
   then relaunching, or toggling the connection off/on from
   System Settings → General → Login Items & Extensions → Tailscale, if
   present.
4. **Reboot the machine** as a last resort, forcing both VPN daemons to
   reinitialize cleanly and clearing any stuck kernel-level routing/pf state.

**What did NOT fix it** (observed this occurrence): quitting and reopening
just the Tailscale menu-bar app. The client/daemon version mismatch and the
TCP timeouts both persisted across that restart.

## Diagnostic Commands

```bash
tailscale status
tailscale version
tailscale netcheck
tailscale ping -c 2 <hostname>
ifconfig | grep -B2 utun
netstat -rn -f inet | grep -iE "^default|100\.|utun"
ps aux | grep -i tailscale
dig +short <host>.exnada.com
```

## Related

- [DNS Issues](dns-issues.md): for DNS problems once you've confirmed this
  isn't a general transport/VPN-conflict issue.
- [Reverse Proxy Issues](reverse-proxy-issues.md): for problems reaching a
  service once basic Tailscale connectivity to the host is confirmed working.
