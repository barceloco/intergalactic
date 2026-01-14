#!/bin/bash
# Diagnose why dev.exnada.com is not accessible
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Diagnosing dev.exnada.com Routing Issue"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Checking Traefik Container Status"
echo "----------------------------------------"
if docker ps --format "{{.Names}}" | grep -q "^traefik$"; then
    echo -e "${GREEN}✓${NC} Traefik is running"
    docker ps --filter "name=traefik"
elif docker ps --format "{{.Names}}" | grep -q traefik; then
    echo -e "${GREEN}✓${NC} Traefik is running (found by partial match)"
    docker ps --filter "name=traefik"
else
    echo -e "${YELLOW}⚠${NC} Traefik container not found with 'docker ps'"
    echo "Checking all containers (including stopped)..."
    docker ps -a | grep traefik || echo "No traefik container found"
    echo ""
    echo "Continuing with other checks..."
fi
echo ""

echo "2. Checking Traefik Dynamic Configuration"
echo "----------------------------------------"
if [[ -f "/opt/traefik/dynamic.yml" ]]; then
    echo "dev.exnada.com route configuration:"
    grep -A 10 "router-dev" /opt/traefik/dynamic.yml | head -15 || echo "Route not found"
    echo ""
    echo "dev.exnada.com service configuration:"
    grep -A 5 "service-dev" /opt/traefik/dynamic.yml | head -10 || echo "Service not found"
else
    echo -e "${RED}✗${NC} /opt/traefik/dynamic.yml not found"
fi
echo ""

echo "3. Checking Container on rigel:8000"
echo "----------------------------------------"
echo "Checking if something is listening on port 8000:"
if netstat -tuln 2>/dev/null | grep -q ":8000 " || ss -tuln 2>/dev/null | grep -q ":8000 "; then
    echo -e "${GREEN}✓${NC} Port 8000 is in use"
    netstat -tuln 2>/dev/null | grep ":8000 " || ss -tuln 2>/dev/null | grep ":8000 "
else
    echo -e "${RED}✗${NC} Nothing listening on port 8000 on the host"
    echo "  This is the problem! The container needs to expose port 8000 to the host."
fi
echo ""

echo "Checking Docker containers:"
echo "Containers with 'aispector' in name:"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "aispector|NAMES" || echo "No aispector containers found"
echo ""

echo "Checking aispector-api container details:"
if docker ps --format "{{.Names}}" | grep -q "aispector-api"; then
    echo "Container network info:"
    docker inspect aispector-api --format '{{range .NetworkSettings.Networks}}{{.NetworkID}} {{.IPAddress}}{{end}}' 2>/dev/null || echo "Could not inspect container"
    echo ""
    echo "Container port bindings:"
    docker inspect aispector-api --format '{{json .HostConfig.PortBindings}}' 2>/dev/null | python3 -m json.tool 2>/dev/null || docker inspect aispector-api --format '{{.HostConfig.PortBindings}}' 2>/dev/null || echo "No port bindings found"
    echo ""
    echo -e "${YELLOW}⚠${NC} If port bindings are empty, the container is not exposing port 8000 to the host!"
    echo "   You need to add a port mapping: -p 8000:8000 or ports: ['8000:8000']"
else
    echo -e "${RED}✗${NC} aispector-api container not found"
fi
echo ""

echo "4. Testing Backend Connectivity"
echo "----------------------------------------"
echo "Testing localhost:8000..."
if curl -s --max-time 5 http://localhost:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} localhost:8000/health is reachable"
    curl -s --max-time 5 http://localhost:8000/health | head -1
else
    echo -e "${RED}✗${NC} localhost:8000/health is NOT reachable"
fi
echo ""

echo "Testing 127.0.0.1:8000..."
if curl -s --max-time 5 http://127.0.0.1:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} 127.0.0.1:8000/health is reachable"
else
    echo -e "${RED}✗${NC} 127.0.0.1:8000/health is NOT reachable"
fi
echo ""

echo "Testing rigel:8000 (DNS resolution)..."
if curl -s --max-time 5 http://rigel:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} rigel:8000/health is reachable"
else
    echo -e "${RED}✗${NC} rigel:8000/health is NOT reachable"
    echo "  (This is expected if DNS doesn't resolve 'rigel' to localhost)"
fi
echo ""

# Get Tailscale FQDN
TAILSCALE_FQDN=$(tailscale status --json 2>/dev/null | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('Self', {}).get('DNSName', ''))" 2>/dev/null || echo "")
if [[ -n "${TAILSCALE_FQDN}" ]]; then
    echo "Testing ${TAILSCALE_FQDN}:8000 (Tailscale FQDN)..."
    if curl -s --max-time 5 http://${TAILSCALE_FQDN}:8000/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} ${TAILSCALE_FQDN}:8000/health is reachable"
    else
        echo -e "${RED}✗${NC} ${TAILSCALE_FQDN}:8000/health is NOT reachable"
        echo "  This is likely the problem! Traefik is trying to reach this URL."
    fi
else
    echo -e "${YELLOW}⚠${NC} Could not determine Tailscale FQDN"
fi
echo ""

echo "5. Checking What Traefik is Actually Using"
echo "----------------------------------------"
if [[ -f "/opt/traefik/dynamic.yml" ]]; then
    BACKEND_URL=$(grep -A 5 "service-dev" /opt/traefik/dynamic.yml | grep "url:" | sed 's/.*url: *"\(.*\)".*/\1/' || echo "NOT FOUND")
    echo "Backend URL in Traefik config: ${BACKEND_URL}"
    if [[ "${BACKEND_URL}" != "NOT FOUND" ]]; then
        echo "Testing ${BACKEND_URL}..."
        if curl -s --max-time 5 ${BACKEND_URL}/health >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Backend URL is reachable"
        else
            echo -e "${RED}✗${NC} Backend URL is NOT reachable - THIS IS THE PROBLEM!"
        fi
    fi
fi
echo ""

echo "6. Testing Traefik Route Directly"
echo "----------------------------------------"
echo "Testing dev.exnada.com via Traefik (localhost:443):"
RESPONSE=$(curl -s -k --max-time 5 -H "Host: dev.exnada.com" https://localhost/health 2>&1 || echo "FAILED")
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 5 -H "Host: dev.exnada.com" https://localhost/ 2>&1 || echo "000")

if [[ "${HTTP_CODE}" == "200" ]] || echo "${RESPONSE}" | grep -q "health\|ok"; then
    echo -e "${GREEN}✓${NC} Route is working (HTTP ${HTTP_CODE})"
    echo "${RESPONSE}" | head -3
elif [[ "${HTTP_CODE}" == "404" ]]; then
    echo -e "${RED}✗${NC} 404 Not Found - Route not configured or backend unreachable"
elif [[ "${HTTP_CODE}" == "502" ]] || [[ "${HTTP_CODE}" == "503" ]]; then
    echo -e "${RED}✗${NC} ${HTTP_CODE} Bad Gateway - Backend is unreachable"
    echo "  This means Traefik can't reach the backend service"
else
    echo -e "${YELLOW}⚠${NC} Unexpected response (HTTP ${HTTP_CODE})"
    echo "${RESPONSE}" | head -3
fi
echo ""

echo "7. Traefik Logs (Recent Errors)"
echo "----------------------------------------"
echo "Last 20 lines with errors/warnings:"
docker logs traefik 2>&1 | tail -50 | grep -i "error\|warn\|dev\.exnada\|rigel" || echo "No recent errors found"
echo ""

echo "8. DNS Resolution Check"
echo "----------------------------------------"
echo "Resolving dev.exnada.com:"
dig @127.0.0.1 dev.exnada.com +short 2>/dev/null || echo "DNS resolution failed"
echo ""

echo "Resolving rigel (should resolve to localhost or Tailscale IP):"
getent hosts rigel 2>/dev/null || echo "rigel not in /etc/hosts"
getent hosts rigel.tailb821ac.ts.net 2>/dev/null || echo "rigel.tailb821ac.ts.net not resolvable"
echo ""

echo "============================================================================"
echo "Diagnostic Summary"
echo "============================================================================"
echo ""
echo "Most likely issues:"
echo "1. Container is only listening on localhost, but Traefik is trying to reach"
echo "   it via Tailscale FQDN (rigel.tailb821ac.ts.net:8000)"
echo "2. Container is not running or not listening on port 8000"
echo "3. Traefik configuration needs to be regenerated"
echo ""
echo "Solutions:"
echo "- If container is on localhost only: Change backend to 'http://localhost:8000'"
echo "- If container should be accessible: Ensure it's bound to 0.0.0.0:8000"
echo "- Regenerate Traefik config: Run the edge_ingress Ansible role"
echo "============================================================================"
