#!/bin/bash
# Comprehensive Traefik backend diagnosis
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Traefik Backend Diagnosis"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Show the actual backend URL in config
echo "1. Backend URL in Traefik configuration:"
echo "----------------------------------------"
grep -A 5 "service-aispector" /opt/traefik/dynamic.yml | grep "url:" || echo "URL not found"
echo ""

# 2. Test DNS resolution from host
echo "2. DNS Resolution (from host):"
echo "----------------------------------------"
echo -n "vega.tailb821ac.ts.net resolves to: "
VEGA_IP=$(getent hosts vega.tailb821ac.ts.net | awk '{print $1}' || echo "")
if [[ -n "${VEGA_IP}" ]]; then
    echo -e "${GREEN}${VEGA_IP}${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi
echo ""

# 3. Test DNS resolution from Traefik container
echo "3. DNS Resolution (from Traefik container):"
echo "----------------------------------------"
echo -n "Testing vega.tailb821ac.ts.net from container... "
if docker exec traefik getent hosts vega.tailb821ac.ts.net &>/dev/null; then
    CONTAINER_RESOLUTION=$(docker exec traefik getent hosts vega.tailb821ac.ts.net | awk '{print $1}')
    echo -e "${GREEN}✓${NC} Resolves to: ${CONTAINER_RESOLUTION}"
else
    echo -e "${RED}✗${NC} Does not resolve"
    echo "  This is the problem! Traefik container can't resolve Tailscale hostnames"
fi
echo ""

# 4. Test backend connectivity from host
echo "4. Backend Connectivity (from host):"
echo "----------------------------------------"
echo -n "Testing http://vega.tailb821ac.ts.net:8000/health... "
if curl -s --max-time 5 http://vega.tailb821ac.ts.net:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable"
    curl -s --max-time 5 http://vega.tailb821ac.ts.net:8000/health
else
    echo -e "${RED}✗${NC} Not reachable"
fi
echo ""

# 5. Test backend connectivity from Traefik container
echo "5. Backend Connectivity (from Traefik container):"
echo "----------------------------------------"
echo -n "Testing http://vega.tailb821ac.ts.net:8000/health from container... "
if docker exec traefik wget -qO- --timeout=5 http://vega.tailb821ac.ts.net:8000/health &>/dev/null; then
    echo -e "${GREEN}✓${NC} Reachable"
    docker exec traefik wget -qO- --timeout=5 http://vega.tailb821ac.ts.net:8000/health
else
    echo -e "${RED}✗${NC} Not reachable"
    echo "  Trying with IP address..."
    if [[ -n "${VEGA_IP}" ]]; then
        if docker exec traefik wget -qO- --timeout=5 http://${VEGA_IP}:8000/health &>/dev/null; then
            echo -e "${GREEN}✓${NC} Reachable via IP: ${VEGA_IP}"
            echo "  Solution: Use IP address in backend URL instead of hostname"
        else
            echo -e "${RED}✗${NC} Not reachable via IP either"
        fi
    fi
fi
echo ""

# 6. Check Docker DNS configuration
echo "6. Docker DNS Configuration:"
echo "----------------------------------------"
if [[ -f /etc/docker/daemon.json ]]; then
    echo "Current Docker daemon.json:"
    cat /etc/docker/daemon.json | python3 -m json.tool 2>/dev/null || cat /etc/docker/daemon.json
else
    echo -e "${YELLOW}⚠${NC} /etc/docker/daemon.json does not exist"
    echo "  Docker is using default DNS (systemd-resolved or 8.8.8.8)"
fi
echo ""

# 7. Check Traefik logs for backend errors
echo "7. Traefik Backend Errors (last 30 lines):"
echo "----------------------------------------"
docker logs traefik 2>&1 | tail -30 | grep -i "backend\|503\|502\|error\|vega" || echo "No backend errors found"
echo ""

# 8. Test Traefik routing
echo "8. Traefik Routing Test:"
echo "----------------------------------------"
echo -n "Testing https://aispector.exnada.com/health... "
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓${NC} Working! (HTTP ${HTTP_CODE})"
    curl -s -k --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health
elif [[ "${HTTP_CODE}" == "503" ]]; then
    echo -e "${RED}✗${NC} 503 Service Unavailable"
    echo "  This means Traefik can't reach the backend"
elif [[ "${HTTP_CODE}" == "502" ]]; then
    echo -e "${RED}✗${NC} 502 Bad Gateway"
    echo "  This means Traefik can't reach the backend"
else
    echo -e "${YELLOW}⚠${NC} HTTP ${HTTP_CODE}"
fi
echo ""

# Summary and recommendations
echo "============================================================================"
echo "Diagnosis Summary"
echo "============================================================================"

if docker exec traefik getent hosts vega.tailb821ac.ts.net &>/dev/null; then
    echo -e "${GREEN}✓${NC} DNS resolution works from Traefik container"
else
    echo -e "${RED}✗${NC} DNS resolution FAILS from Traefik container"
    echo ""
    echo "SOLUTION: Configure Docker to use CoreDNS (127.0.0.1) for DNS"
    echo "Run: bash /tmp/fix-traefik-backend-url.sh"
    echo "Or manually:"
    echo "  1. Edit /etc/docker/daemon.json to add: {\"dns\": [\"127.0.0.1\", \"8.8.8.8\"]}"
    echo "  2. Restart Docker: sudo systemctl restart docker"
    echo "  3. Restart Traefik: cd /opt/traefik && docker compose restart traefik"
fi

if [[ -n "${VEGA_IP}" ]] && docker exec traefik wget -qO- --timeout=5 http://${VEGA_IP}:8000/health &>/dev/null; then
    echo -e "${GREEN}✓${NC} Backend is reachable via IP from Traefik container"
    echo ""
    echo "ALTERNATIVE SOLUTION: Use IP address in backend URL"
    echo "  Edit /opt/traefik/dynamic.yml and change:"
    echo "    url: \"http://vega.tailb821ac.ts.net:8000\""
    echo "  To:"
    echo "    url: \"http://${VEGA_IP}:8000\""
    echo "  Then restart Traefik"
fi

echo "============================================================================"
