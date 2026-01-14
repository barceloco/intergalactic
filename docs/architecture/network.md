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
│  │ CoreDNS  │◄───┤ AISpector│    │  NAS     │              │
│  │ Traefik  │    │          │    │          │              │
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

1. User requests `https://aispector.exnada.com`
2. Public DNS resolves to rigel's public IP
3. HTTPS connection to Traefik
4. Traefik routes to backend via Tailscale

## Security

### Encryption

- **Tailscale**: WireGuard-based encryption
- **HTTPS**: TLS encryption for external traffic
- **Internal**: All traffic encrypted via Tailscale

### Access Control

- **Tailscale ACLs**: Control which hosts can communicate
- **Firewall**: nftables on each host
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

### rigel

- **53**: CoreDNS (DNS)
- **80**: Traefik (HTTP)
- **443**: Traefik (HTTPS)

### vega

- **8000**: AISpector service

### mpnas

- **5000**: NAS services
