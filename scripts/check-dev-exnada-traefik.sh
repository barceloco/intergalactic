#!/bin/bash
# Check Traefik configuration for dev.exnada.com
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Checking dev.exnada.com Traefik Configuration"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Testing Backend Directly"
echo "----------------------------------------"
echo "Testing rigel:8000/health..."
if curl -s --max-time 5 http://rigel:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} rigel:8000/health is reachable"
    curl -s --max-time 5 http://rigel:8000/health
else
    echo -e "${RED}✗${NC} rigel:8000/health is NOT reachable"
fi
echo ""

echo "Testing localhost:8000/health..."
if curl -s --max-time 5 http://localhost:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} localhost:8000/health is reachable"
    curl -s --max-time 5 http://localhost:8000/health
else
    echo -e "${RED}✗${NC} localhost:8000/health is NOT reachable"
fi
echo ""

echo "2. Traefik Configuration"
echo "----------------------------------------"
# Check where Traefik config might be
CONFIG_DIRS=("/opt/traefik" "/etc/traefik" "/var/lib/traefik")
DYNAMIC_FILE=""

for dir in "${CONFIG_DIRS[@]}"; do
    if [[ -f "${dir}/dynamic.yml" ]]; then
        DYNAMIC_FILE="${dir}/dynamic.yml"
        echo -e "${GREEN}✓${NC} Found dynamic.yml at ${DYNAMIC_FILE}"
        break
    fi
done

if [[ -z "${DYNAMIC_FILE}" ]]; then
    echo -e "${RED}✗${NC} dynamic.yml not found in standard locations"
    echo "Checking Traefik container mounts for config location..."
    docker inspect traefik --format '{{range .Mounts}}{{if or (eq .Destination "/dynamic.yml") (contains .Destination "traefik")}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}{{end}}' 2>/dev/null || echo "Could not inspect container"
    echo ""
    echo "Checking if /opt/traefik exists:"
    ls -la /opt/traefik 2>/dev/null || echo "  /opt/traefik does not exist"
    echo ""
    echo -e "${YELLOW}⚠${NC} Traefik configuration file is missing!"
    echo "  You need to create /opt/traefik/dynamic.yml with the route configuration"
    echo "  Or run the Ansible edge_ingress role to deploy it properly"
    echo ""
else
    echo "dev.exnada.com router configuration:"
    grep -B 2 -A 8 "router-dev" "${DYNAMIC_FILE}" | head -15 || echo "Router not found"
    echo ""
    echo "dev.exnada.com service configuration:"
    grep -B 2 -A 8 "service-dev" "${DYNAMIC_FILE}" | head -15 || echo "Service not found"
    echo ""
    
    # Extract backend URL
    BACKEND_URL=$(grep -A 10 "service-dev" "${DYNAMIC_FILE}" | grep "url:" | sed 's/.*url: *"\(.*\)".*/\1/' | head -1 || echo "")
    if [[ -n "${BACKEND_URL}" ]]; then
        echo "Backend URL configured: ${BACKEND_URL}"
        echo ""
        echo "Testing backend URL from Traefik's perspective..."
        # Test if Traefik can reach it (Traefik uses host networking)
        if curl -s --max-time 5 ${BACKEND_URL}/health >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Backend URL is reachable"
            curl -s --max-time 5 ${BACKEND_URL}/health
        else
            echo -e "${RED}✗${NC} Backend URL is NOT reachable"
            echo "  This is the problem! Traefik can't reach the backend."
        fi
    else
        echo -e "${RED}✗${NC} Could not find backend URL in configuration"
    fi
fi
echo ""

echo "3. Traefik Container Status"
echo "----------------------------------------"
if docker ps --format "{{.Names}}" | grep -q "traefik"; then
    echo -e "${GREEN}✓${NC} Traefik container is running"
    docker ps --filter "name=traefik" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
else
    echo -e "${RED}✗${NC} Traefik container not found"
    echo "All running containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}"
fi
echo ""

echo "4. Testing Traefik Route"
echo "----------------------------------------"
echo "Testing dev.exnada.com via Traefik (localhost:443):"
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: dev.exnada.com" https://localhost/ 2>&1 || echo "000")
RESPONSE=$(curl -s -k --max-time 10 -H "Host: dev.exnada.com" https://localhost/health 2>&1 || echo "FAILED")

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓${NC} Route is working (HTTP ${HTTP_CODE})"
    echo "Response: ${RESPONSE}"
elif [[ "${HTTP_CODE}" == "404" ]]; then
    echo -e "${RED}✗${NC} 404 Not Found - Route not configured or backend unreachable"
    echo "Response: ${RESPONSE}"
elif [[ "${HTTP_CODE}" == "502" ]] || [[ "${HTTP_CODE}" == "503" ]]; then
    echo -e "${RED}✗${NC} ${HTTP_CODE} Bad Gateway - Backend is unreachable from Traefik"
    echo "Response: ${RESPONSE}"
    echo ""
    echo "This means Traefik can't reach the backend URL configured in dynamic.yml"
elif [[ "${HTTP_CODE}" == "000" ]]; then
    echo -e "${RED}✗${NC} Connection failed - Traefik may not be running or port 443 not accessible"
else
    echo -e "${YELLOW}⚠${NC} Unexpected response (HTTP ${HTTP_CODE})"
    echo "Response: ${RESPONSE}"
fi
echo ""

echo "5. Traefik Logs (Recent Errors for dev.exnada.com)"
echo "----------------------------------------"
if docker ps --format "{{.Names}}" | grep -q "traefik"; then
    echo "Last 30 lines with dev.exnada.com or errors:"
    docker logs traefik 2>&1 | tail -50 | grep -i "error\|warn\|dev\.exnada\|rigel\|8000" || echo "No recent errors found"
    echo ""
    echo "Last 20 lines of Traefik logs (general):"
    docker logs traefik 2>&1 | tail -20
else
    echo "Traefik container not running, cannot check logs"
fi
echo ""

echo "6. DNS Resolution"
echo "----------------------------------------"
echo "Resolving dev.exnada.com:"
dig @127.0.0.1 dev.exnada.com +short 2>/dev/null || echo "DNS resolution failed"
echo ""

echo "Resolving rigel:"
getent hosts rigel 2>/dev/null || echo "rigel not in /etc/hosts"
echo ""

echo "============================================================================"
echo "Summary"
echo "============================================================================"
echo "If backend is reachable but Traefik returns 502/503:"
echo "  - Check the backend URL in /opt/traefik/dynamic.yml"
echo "  - Ensure it matches how Traefik can reach the service"
echo "  - Traefik uses host networking, so 'localhost:8000' should work"
echo ""
echo "If you see 404:"
echo "  - Route may not be configured in Traefik"
echo "  - Check /opt/traefik/dynamic.yml for router-dev and service-dev"
echo "============================================================================"
