# Reverse Proxy Architecture

## Overview

Traefik provides HTTPS termination, TLS certificate management, and request routing for the intergalactic infrastructure.

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ HTTPS (443)
       ▼
┌─────────────────────────────────────┐
│         Traefik (rigel)             │
│  ┌──────────────────────────────┐  │
│  │  Entrypoints                  │  │
│  │  - web (80): HTTP             │  │
│  │  - websecure (443): HTTPS     │  │
│  └──────────────────────────────┘  │
│  ┌──────────────────────────────┐  │
│  │  Routers                      │  │
│  │  - Host-based routing         │  │
│  │  - TLS termination            │  │
│  └──────────────────────────────┘  │
│  ┌──────────────────────────────┐  │
│  │  Services                     │  │
│  │  - Backend URLs               │  │
│  │  - Health checks              │  │
│  │  - Load balancing             │  │
│  └──────────────────────────────┘  │
│  ┌──────────────────────────────┐  │
│  │  Middlewares                  │  │
│  │  - Security headers            │  │
│  │  - Retry logic                 │  │
│  └──────────────────────────────┘  │
└──────┬─────────────────────────────┘
       │ HTTP
       ▼
┌─────────────────────────────────────┐
│      Backend Services                │
│  - vega:8000 (AISpector)            │
│  - Other services                    │
└─────────────────────────────────────┘
```

## Configuration

### Static Configuration (traefik.yml)

- Entrypoints (HTTP/HTTPS ports)
- Certificate resolvers (ACME/Let's Encrypt)
- Providers (file-based configuration)

### Dynamic Configuration (dynamic.yml)

- Routers (host-based routing rules)
- Services (backend URLs and health checks)
- Middlewares (security headers, retry)

## Request Flow

1. **Client Request**: `https://aispector.exnada.com/health`
2. **TLS Termination**: Traefik terminates HTTPS
3. **Router Matching**: Matches host `aispector.exnada.com`
4. **Middleware Application**: Applies security headers
5. **Service Routing**: Routes to `http://vega.tailb821ac.ts.net:8000`
6. **Backend Request**: Traefik makes HTTP request to backend
7. **Response**: Backend responds
8. **Client Response**: Traefik returns HTTPS response

## TLS Certificate Management

### ACME/Let's Encrypt

- **Challenge Type**: DNS-01 (GoDaddy API)
- **Automatic Renewal**: Traefik handles renewal
- **Storage**: `acme.json` file (encrypted)

### Certificate Lifecycle

1. **Initial Request**: Traefik requests certificate for domain
2. **DNS Challenge**: Creates TXT record via GoDaddy API
3. **Validation**: Let's Encrypt validates DNS record
4. **Certificate Issued**: Certificate stored in `acme.json`
5. **Auto-Renewal**: Traefik renews before expiration

## Routing Rules

### Host-Based Routing

```yaml
routers:
  router-aispector:
    rule: "Host(`aispector.exnada.com`)"
    entryPoints:
      - websecure
    service: service-aispector
    tls:
      certResolver: letsencrypt
```

### Service Configuration

```yaml
services:
  service-aispector:
    loadBalancer:
      servers:
        - url: "http://vega.tailb821ac.ts.net:8000"
      healthCheck:
        path: "/health"
        interval: "10s"
        timeout: "3s"
```

## Middlewares

### Security Headers

- HSTS (Strict-Transport-Security)
- X-Frame-Options
- X-Content-Type-Options
- X-XSS-Protection

### Retry Logic

- Automatic retry on backend failures
- Configurable retry attempts

## Health Checks

- **Path**: `/health` (configurable)
- **Interval**: 10 seconds
- **Timeout**: 3 seconds
- **Failure Threshold**: 3 consecutive failures

## HTTP to HTTPS Redirect

- **Entrypoint-level**: Automatic redirect from HTTP (80) to HTTPS (443)
- **Permanent**: 301 redirect

## Monitoring

- **API**: Traefik dashboard (if enabled)
- **Logs**: Structured JSON logging
- **Metrics**: Request rates, latency, error rates
