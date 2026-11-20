# Network Architecture

## Overview

The intergalactic infrastructure uses Tailscale VPN to provide secure, encrypted connectivity between hosts.

## Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    Tailscale Network                        │
│                  (100.x.x.x addresses)                      │
│                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │  rigel   │    │   vega   │    │  mpnas   │              │
│  │          │    │          │    │          │              │
│  │ CoreDNS  │◄───┤ aispector│    │  NAS     │              │
│  │ Traefik  │    │ callosal │    │  immich  │              │
│  │ csa, demo│    │ docgen   │    │          │              │
│  │ Grafana  │    │ Samba    │    │          │              │
│  └──────────┘    └──────────┘    └──────────┘              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Tailscale Configuration

### FQDN Resolution

- Each host has a Tailscale FQDN: `hostname.tailnet.ts.net`
- Example: `vega.tailb821ac.ts.net`
- Automatic DNS resolution within Tailscale network

### IP Addresses

- **Format**: 100.x.x.x (Tailscale IP range)
- **Assignment**: Automatic by Tailscale
- **Persistence**: IPs remain stable per host

## Service Discovery

### Internal DNS (CoreDNS)

- Resolves internal hostnames to Tailscale IPs
- Example: `vega.exnada.com` → `100.116.12.30`

### FQDN Usage

- Backend services use Tailscale FQDNs
- Example: `http://vega.tailb821ac.ts.net:8000`
- Ensures connectivity even if IPs change

## Network Flow

### Internal Communication

1. Service needs to reach `vega:8000`
2. CoreDNS resolves to Tailscale IP
3. Traffic routed through Tailscale VPN
4. Encrypted tunnel ensures security

### External Access

The app domains are tailnet-only: they have no public DNS records.

1. A tailnet device requests `https://aispector.exnada.com`
2. Tailscale DNS sends the query to CoreDNS on rigel, which answers with
   rigel's Tailscale IP
3. HTTPS connection to Traefik on rigel, over Tailscale
4. Traefik routes to the backend: locally on rigel, or over Tailscale to
   vega, whose firewall admits only rigel's address on the backend ports

## Security

### Encryption

- **Tailscale**: WireGuard-based encryption
- **HTTPS**: TLS encryption for external traffic
- **Internal**: All traffic encrypted via Tailscale

### Access Control

- **Tailscale ACLs**: Control which hosts can communicate
- **Firewall**: nftables allow-list on each host, on every interface including
  Tailscale and including Docker-published ports. LAN devices reach only SSH,
  ping and Samba; see `firewall_rules` in host_vars
- **SSH**: Key-based authentication

## Network Resilience

### Failover

- **Tailscale**: Automatic reconnection on network changes
- **DNS**: Multiple upstream servers
- **Services**: Auto-restart on failure

### Monitoring

- **Connectivity**: Tailscale status checks
- **Latency**: Network latency monitoring
- **Bandwidth**: Traffic monitoring

## Port Usage

Observed on the hosts on 2026-11-04. Full detail and known drift:
[fleet-state.md](fleet-state.md).

### rigel

- **53**: CoreDNS (DNS)
- **80**: Traefik (HTTP)
- **443**: Traefik (HTTPS)
- **8001**: callosal dev (demo.exnada.com)
- **8023**: csa (csa.exnada.com)
- **139, 445**: Samba

### vega

- **8000**: aispector API (aispector.exnada.com)
- **8001**: callosal (callosal.exnada.com)
- **8048**: docgen (docgen.exnada.com)
- **139, 445**: Samba
- **5432, 6379, 9000, 9001**: aispector Postgres, Redis, MinIO (published on all interfaces; see drift in fleet-state.md)

### mpnas

- **5000**: NAS services (not audited; mpnas is not Ansible-managed)
- **2283**: immich (immich.exnada.com, via Traefik on rigel)
