# Infrastructure Architecture Overview

## High-Level Architecture

The intergalactic infrastructure provides DNS resolution, reverse proxy, and service routing for internal services across multiple hosts connected via Tailscale VPN.

```
┌─────────────────────────────────────────────────────────────┐
│                    External Users                            │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTPS (443)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Traefik (Reverse Proxy)                                    │
│  - HTTPS termination                                         │
│  - TLS certificate management (ACME/Let's Encrypt)          │
│  - Request routing                                          │
│  - Health checks                                             │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTP
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Backend Services                                            │
│  - AISpector (vega:8000)                                     │
│  - Other services                                            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  CoreDNS (Internal DNS)                                     │
│  - Internal hostname resolution                              │
│  - External DNS forwarding                                   │
│  - Split-horizon DNS                                        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Tailscale VPN                                               │
│  - Network connectivity                                      │
│  - FQDN resolution                                           │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. CoreDNS (Internal DNS)
- **Purpose**: Provides DNS resolution for internal hosts
- **Location**: rigel (port 53)
- **Features**:
  - Resolves internal hostnames to Tailscale IPs
  - Forwards external queries to upstream DNS servers
  - Split-horizon DNS (internal vs external)

### 2. Traefik (Reverse Proxy)
- **Purpose**: HTTPS termination and request routing
- **Location**: rigel (ports 80, 443)
- **Features**:
  - Automatic TLS certificate management (ACME/Let's Encrypt)
  - HTTP to HTTPS redirect
  - Health checks for backends
  - Security headers middleware

### 3. Backend Services
- **Purpose**: Application services
- **Examples**: AISpector, dev services
- **Access**: Via Traefik reverse proxy

### 4. Tailscale VPN
- **Purpose**: Secure network connectivity
- **Features**: FQDN resolution, encrypted tunnels

## Data Flow

### Request Flow
1. User requests `https://aispector.exnada.com/health`
2. DNS resolves `aispector.exnada.com` to rigel's Tailscale IP
3. HTTPS connection established to Traefik
4. Traefik terminates TLS and routes to backend
5. Backend responds
6. Traefik returns response to user

### DNS Resolution Flow
1. Client queries CoreDNS for `vega.exnada.com`
2. CoreDNS checks internal zone file
3. Returns Tailscale IP address
4. For external domains, forwards to upstream DNS

## Network Architecture

- **Internal Network**: Tailscale VPN (100.x.x.x)
- **External Access**: Via public IPs and DNS
- **Service Discovery**: CoreDNS provides internal DNS
- **Load Balancing**: Traefik handles routing

## Security

- **TLS/SSL**: Automatic certificate management via ACME
- **Network**: Tailscale VPN provides encrypted tunnels
- **Firewall**: nftables on each host
- **Access Control**: SSH key-based authentication

## High Availability

- **Current**: Single instance of each service
- **Future**: Can be extended with redundancy
- **Recovery**: Systemd services ensure auto-restart

## Monitoring

- **Health Checks**: Automated health monitoring
- **Logging**: Structured JSON logging
- **Metrics**: Performance metrics collection
- **Alerting**: Automated alerting for failures
