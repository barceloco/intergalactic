# firewall_nftables Role

An allow-list firewall. Every interface, Tailscale included, denies by default,
and every open port names the sources allowed to reach it. The same allow-list
covers Docker-published container ports.

## Policy

| Traffic | Allowed from |
|---|---|
| SSH (`ssh_port`) | tailnet and `firewall_lan_subnet`, always (the LAN path is the lockout backup and cannot be disabled) |
| Ping | tailnet and `firewall_lan_subnet` |
| IPv6 neighbour discovery | the local link (hop limit 255) |
| Tailscale transport, udp 41641 | anywhere (if `enable_tailscale`) |
| DNS 53 tcp/udp | tailnet (if `internal_dns_enabled`) |
| HTTP/HTTPS 80, 443 | tailnet (if `edge_ingress_enabled`) |
| Anything in `firewall_rules` | the sources that rule names |
| Everything else | dropped and logged (rate-limited) |

## Why containers need special handling

Docker publishes a port by rewriting its destination (DNAT) before routing, so
the packet goes through the **forward** path and never reaches the input chain.
An input-only firewall therefore leaves every `0.0.0.0` publish open to the LAN
and the tailnet. This role filters new DNAT'd connections in the forward chain
against the same allow-list, matching the port the client originally connected
to (`ct original proto-dst`), since Docker rewrites it. A drop in this table is
final even though Docker's own chains accept the packet later. Container
traffic on Docker bridges (`docker0`, `br-*`) and replies stay untouched.

## Variables

| Variable | Default | Description |
|---|---|---|
| `firewall_lan_subnet` | `192.168.1.0/24` | The local LAN (source `lan`). Required. |
| `fleet_tailscale_ipv4` | `{}` | Host name to Tailscale IPv4, so a rule can admit one host |
| `firewall_rules` | `[]` | Per-host rules, see below |
| `firewall_rate_limit` | `10` | Max logged drops per second |
| `enable_tailscale`, `enable_docker`, `internal_dns_enabled`, `edge_ingress_enabled` | | Enable the matching built-in rules |

Each `firewall_rules` entry:

```yaml
firewall_rules:
  - port: 8000              # a port or a list of ports
    proto: tcp              # tcp (default) or udp
    from: [rigel]           # "tailnet", "lan", or a host in fleet_tailscale_ipv4
    comment: "aispector backend for Traefik on rigel"   # required
```

A host source matches only on `tailscale0` and only that host's address, so the
same address arriving on the LAN wire (a spoof) is dropped.

The role validates everything before touching the host and refuses the retired
`firewall_allow_tcp_ports`, `firewall_allow_udp_ports`, `docker_deploy_tcp_ports`
(they opened ports to all sources) and `firewall_local_ssh_subnet` (renamed to
`firewall_lan_subnet`).

## Reviewing and deploying

```bash
./scripts/render-firewall.sh <host>     # exact rules, validated and nft -c checked; touches nothing
./scripts/run-ansible.sh prod <host> foundation --tags security
```

The rules file is syntax-checked before it replaces `/etc/nftables.conf`. Only
the `inet filter` table is replaced; Docker's tables are left alone, so a
reload is safe while containers run.

## Testing

`./scripts/run-molecule-tests.sh firewall_nftables` converges a vega-shaped
config on Debian trixie, then builds a fake tailnet (an interface named
`tailscale0` carrying rigel's and another node's addresses), a LAN (LAN,
non-LAN and spoofed sources) and a container behind a DNAT'd published port.
It sends real TCP connections and pings and checks each against the policy,
and checks that the retired variables are refused.

## Troubleshooting

- See what is dropped: `journalctl -k -g 'nft-in-drop|nft-fwd-drop'`
- See the loaded rules: `sudo nft list table inet filter`
- A port that must be reachable is missing: add it to the host's
  `firewall_rules` with the narrowest source, render, review, deploy.
