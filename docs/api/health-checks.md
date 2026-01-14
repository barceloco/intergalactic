# Health Check API Documentation

## Overview

Health check endpoints provide status information for services and infrastructure components.

## Endpoints

### Backend Service Health

**Endpoint**: `GET /health`

**Description**: Returns health status of backend services

**Example Request**:
```bash
curl https://aispector.exnada.com/health
```

**Example Response**:
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "service": "AISpector Server"
}
```

**Status Codes**:
- `200 OK`: Service is healthy
- `503 Service Unavailable`: Service is unhealthy or unavailable
- `404 Not Found`: Health endpoint not configured

### Traefik API

**Endpoint**: `GET http://localhost:8080/api/http/services`

**Description**: Returns Traefik service configuration (if API enabled)

**Example Request**:
```bash
curl http://localhost:8080/api/http/services
```

**Response**: JSON object with service configurations

### CoreDNS Health

**Endpoint**: DNS query to `@127.0.0.1`

**Description**: Tests DNS resolution

**Example Request**:
```bash
dig @127.0.0.1 exnada.com
```

**Response**: DNS response with NOERROR status

## Health Check Script

**Location**: `/usr/local/bin/health-check.sh`

**Usage**:
```bash
/usr/local/bin/health-check.sh
```

**Output**: Status of all components (Docker, Tailscale, CoreDNS, Traefik)

**Exit Codes**:
- `0`: All checks passed
- `1`: One or more checks failed

## Monitoring

### Systemd Timer

Health checks run automatically via systemd timer:

```bash
systemctl status health-monitor.timer
```

### Logs

Health check results are logged to systemd journal:

```bash
journalctl -u health-monitor
```

## Integration

### Ansible Validation

Health checks are integrated into Ansible validation tasks:

- DNS resolution validation
- Traefik connectivity validation
- Backend health validation

### Monitoring Scripts

Health checks can be integrated into monitoring systems:

- Prometheus exporters
- Nagios checks
- Custom monitoring scripts
