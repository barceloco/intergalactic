# DNS Architecture

## Overview

CoreDNS provides internal DNS resolution for the intergalactic infrastructure, implementing split-horizon DNS to serve internal hosts while forwarding external queries.

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ DNS Query
       ▼
┌─────────────────────────────────────┐
│         CoreDNS (rigel:53)          │
│  ┌──────────────────────────────┐  │
│  │  Internal Zone File           │  │
│  │  - vega.exnada.com            │  │
│  │  - mpnas.exnada.com           │  │
│  │  - aispector.exnada.com       │  │
│  └──────────────────────────────┘  │
│  ┌──────────────────────────────┐  │
│  │  Forward Plugin               │  │
│  │  - External domains            │  │
│  │  - Upstream: 8.8.8.8, 8.8.4.4 │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Configuration

### Corefile Structure

```corefile
.:53 {
    file db.exnada.com {
        reload 30s
    }
    forward . 8.8.8.8 8.8.4.4
    log
    errors
}
```

### Zone File Format

```
$ORIGIN exnada.com.
$TTL 3600

@       IN SOA  rigel.exnada.com. admin.exnada.com. (
                 2024010101  ; serial
                 3600        ; refresh
                 1800        ; retry
                 604800      ; expire
                 86400       ; minimum
                )

@       IN NS   rigel.exnada.com.

vega    IN A    100.116.12.30
mpnas   IN A    100.120.170.43
rigel   IN A    100.xxx.xxx.xxx
```

## DNS Resolution Flow

### Internal Domain Resolution

1. Client queries CoreDNS for `vega.exnada.com`
2. CoreDNS checks zone file
3. Returns A record with Tailscale IP
4. Client connects to service

### External Domain Resolution

1. Client queries CoreDNS for `google.com`
2. CoreDNS checks zone file (not found)
3. Forwards query to upstream DNS (8.8.8.8)
4. Returns result to client

### Reverse-Proxy Host Resolution

For hosts served via Traefik (e.g., `aispector.exnada.com`):
- DNS resolves to rigel's Tailscale IP
- Traefik handles routing to actual backend

## Split-Horizon DNS

- **Internal**: Resolves to Tailscale IPs
- **External**: Forwards to public DNS
- **Benefit**: Internal services use Tailscale network, external services use public internet

## Failover and Reliability

- **Upstream DNS**: Multiple upstream servers (8.8.8.8, 8.8.4.4)
- **Auto-restart**: Systemd service ensures CoreDNS restarts on failure
- **Health Checks**: DNS queries verify CoreDNS is responding

## Monitoring

- **Query Logging**: CoreDNS logs all queries
- **Health Checks**: Regular DNS resolution tests
- **Metrics**: Query rate and latency tracking
