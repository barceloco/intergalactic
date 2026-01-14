#!/bin/bash
# Create Traefik dynamic.yml configuration for dev.exnada.com
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Creating Traefik Configuration for dev.exnada.com"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TRAEFIK_DIR="/opt/traefik"
DYNAMIC_FILE="${TRAEFIK_DIR}/dynamic.yml"

# Check if directory exists
if [[ ! -d "${TRAEFIK_DIR}" ]]; then
    echo "Creating ${TRAEFIK_DIR} directory..."
    sudo mkdir -p "${TRAEFIK_DIR}"
    sudo chown root:root "${TRAEFIK_DIR}"
    sudo chmod 755 "${TRAEFIK_DIR}"
fi

# Check if file already exists
if [[ -f "${DYNAMIC_FILE}" ]]; then
    echo -e "${YELLOW}⚠${NC} ${DYNAMIC_FILE} already exists"
    echo "Backing up to ${DYNAMIC_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    sudo cp "${DYNAMIC_FILE}" "${DYNAMIC_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Test backend connectivity
echo "Testing backend connectivity..."
if curl -s --max-time 5 http://rigel:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Backend rigel:8000 is reachable"
    BACKEND_URL="http://rigel:8000"
else
    echo -e "${RED}✗${NC} Backend rigel:8000 is NOT reachable"
    echo "Please ensure the service is running on port 8000"
    exit 1
fi

# Create the dynamic.yml file
echo ""
echo "Creating ${DYNAMIC_FILE}..."
sudo tee "${DYNAMIC_FILE}" > /dev/null <<'EOF'
http:
  middlewares:
    security-headers:
      headers:
        sslRedirect: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        customFrameOptionsValue: "SAMEORIGIN"
        customRequestHeaders:
          X-Forwarded-Proto: "https"
        customResponseHeaders:
          X-Content-Type-Options: "nosniff"
          X-Frame-Options: "SAMEORIGIN"
          X-XSS-Protection: "1; mode=block"
          Referrer-Policy: "strict-origin-when-cross-origin"
          Permissions-Policy: "geolocation=(), microphone=(), camera=()"

    retry:
      retry:
        attempts: 3
        initialInterval: 100ms

  routers:
    router-dev:
      rule: "Host(`dev.exnada.com`)"
      entryPoints:
        - websecure
      service: service-dev
      middlewares:
        - security-headers
        - retry
      tls:
        certResolver: letsencrypt

  services:
    service-dev:
      loadBalancer:
        healthCheck:
          path: "/health"
          interval: "10s"
          timeout: "3s"
          scheme: http
        servers:
          - url: "http://rigel:8000"
EOF

sudo chmod 644 "${DYNAMIC_FILE}"
sudo chown root:root "${DYNAMIC_FILE}"

echo -e "${GREEN}✓${NC} Configuration file created"
echo ""

# Check if Traefik is using this file
echo "Verifying Traefik can see the config..."
if docker ps --format "{{.Names}}" | grep -q "traefik"; then
    echo "Checking Traefik container mounts..."
    docker inspect traefik --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null | grep -i traefik || echo "No traefik mounts found"
    echo ""
    
    echo "Restarting Traefik to pick up new configuration..."
    docker restart traefik
    sleep 5
    
    echo ""
    echo "Testing dev.exnada.com route..."
    HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: dev.exnada.com" https://localhost/health 2>&1 || echo "000")
    
    if [[ "${HTTP_CODE}" == "200" ]]; then
        echo -e "${GREEN}✓${NC} SUCCESS! dev.exnada.com is working (HTTP ${HTTP_CODE})"
        curl -s -k --max-time 10 -H "Host: dev.exnada.com" https://localhost/health
    else
        echo -e "${YELLOW}⚠${NC} Route returned HTTP ${HTTP_CODE}"
        echo "Check Traefik logs: docker logs traefik | tail -20"
    fi
else
    echo -e "${YELLOW}⚠${NC} Traefik container not running"
    echo "Start it with: docker start traefik"
fi

echo ""
echo "============================================================================"
echo "Configuration created at ${DYNAMIC_FILE}"
echo "============================================================================"
