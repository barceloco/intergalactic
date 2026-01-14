#!/bin/bash
# Comprehensive reverse proxy fix and test script
# Run this on rigel to diagnose and fix issues

set -euo pipefail

echo "============================================================================"
echo "Reverse Proxy Diagnostic and Fix"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

# 1. Check Docker
echo "1. Docker Service"
echo "----------------------------------------"
if systemctl is-active --quiet docker; then
    echo -e "${GREEN}✓${NC} Docker is running"
else
    echo -e "${RED}✗${NC} Docker is not running - starting..."
    sudo systemctl start docker
    sudo systemctl enable docker
    sleep 3
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✓${NC} Docker started successfully"
    else
        echo -e "${RED}✗${NC} Failed to start Docker"
        ((ERRORS++))
    fi
fi
echo ""

# 2. Check Tailscale
echo "2. Tailscale Connectivity"
echo "----------------------------------------"
if command -v tailscale &>/dev/null; then
    if tailscale status &>/dev/null; then
        echo -e "${GREEN}✓${NC} Tailscale is connected"
        TAILSCALE_IP=$(tailscale ip -4)
        echo "  Tailscale IP: ${TAILSCALE_IP}"
    else
        echo -e "${RED}✗${NC} Tailscale is not connected"
        echo "  Run: sudo tailscale up"
        ((ERRORS++))
    fi
else
    echo -e "${RED}✗${NC} Tailscale not found"
    ((ERRORS++))
fi
echo ""

# 3. Check CoreDNS
echo "3. CoreDNS Container"
echo "----------------------------------------"
if docker ps | grep -q coredns; then
    echo -e "${GREEN}✓${NC} CoreDNS is running"
    docker ps | grep coredns
else
    echo -e "${YELLOW}⚠${NC} CoreDNS is not running - starting..."
    if [[ -f /opt/coredns/docker-compose.yml ]]; then
        cd /opt/coredns && docker compose up -d
        sleep 3
        if docker ps | grep -q coredns; then
            echo -e "${GREEN}✓${NC} CoreDNS started successfully"
        else
            echo -e "${RED}✗${NC} Failed to start CoreDNS"
            echo "  Logs:"
            docker logs coredns 2>&1 | tail -20
            ((ERRORS++))
        fi
    else
        echo -e "${RED}✗${NC} CoreDNS compose file not found"
        ((ERRORS++))
    fi
fi
echo ""

# 4. Check Traefik
echo "4. Traefik Container"
echo "----------------------------------------"
if docker ps | grep -q traefik; then
    echo -e "${GREEN}✓${NC} Traefik is running"
    docker ps | grep traefik
else
    echo -e "${YELLOW}⚠${NC} Traefik is not running - starting..."
    if [[ -f /opt/traefik/docker-compose.yml ]]; then
        cd /opt/traefik && docker compose up -d
        sleep 3
        if docker ps | grep -q traefik; then
            echo -e "${GREEN}✓${NC} Traefik started successfully"
        else
            echo -e "${RED}✗${NC} Failed to start Traefik"
            echo "  Logs:"
            docker logs traefik 2>&1 | tail -20
            ((ERRORS++))
        fi
    else
        echo -e "${RED}✗${NC} Traefik compose file not found"
        ((ERRORS++))
    fi
fi
echo ""

# 5. Check Traefik Configuration
echo "5. Traefik Configuration"
echo "----------------------------------------"
if [[ -f /opt/traefik/traefik.yml ]]; then
    echo -e "${GREEN}✓${NC} traefik.yml exists"
else
    echo -e "${RED}✗${NC} traefik.yml missing"
    ((ERRORS++))
fi

if [[ -f /opt/traefik/dynamic.yml ]]; then
    echo -e "${GREEN}✓${NC} dynamic.yml exists"
    echo "  Routes configured:"
    grep -E "router-|rule:" /opt/traefik/dynamic.yml | head -5 || echo "  No routes found"
else
    echo -e "${RED}✗${NC} dynamic.yml missing"
    ((ERRORS++))
fi
echo ""

# 6. Test DNS Resolution
echo "6. DNS Resolution"
echo "----------------------------------------"
if dig @127.0.0.1 aispector.exnada.com +short +timeout=2 &>/dev/null; then
    DNS_RESULT=$(dig @127.0.0.1 aispector.exnada.com +short +timeout=2)
    echo -e "${GREEN}✓${NC} aispector.exnada.com resolves to: ${DNS_RESULT}"
else
    echo -e "${RED}✗${NC} aispector.exnada.com does not resolve"
    ((ERRORS++))
fi
echo ""

# 7. Test Backend Connectivity
echo "7. Backend Service Connectivity"
echo "----------------------------------------"
echo -n "Testing vega:8000/health... "
if curl -s --max-time 5 http://vega:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable"
    BACKEND_RESPONSE=$(curl -s --max-time 5 http://vega:8000/health)
    echo "  Response: ${BACKEND_RESPONSE:0:100}"
else
    echo -e "${RED}✗${NC} Not reachable"
    echo "  Trying via Tailscale FQDN..."
    if curl -s --max-time 5 http://vega.tailb821ac.ts.net:8000/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Reachable via Tailscale FQDN"
    else
        echo -e "${RED}✗${NC} Not reachable via Tailscale FQDN either"
        ((ERRORS++))
    fi
fi
echo ""

# 8. Test Traefik Routing
echo "8. Traefik Routing Test"
echo "----------------------------------------"
echo -n "Testing https://aispector.exnada.com/health via Traefik... "
RESPONSE=$(curl -s -k --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "FAILED")
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "000")

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓${NC} Working (HTTP 200)"
    echo "  Response: ${RESPONSE:0:100}"
elif [[ "${HTTP_CODE}" == "404" ]]; then
    echo -e "${RED}✗${NC} 404 Not Found - Route not configured"
    echo "  Checking Traefik logs..."
    docker logs traefik 2>&1 | tail -20 | grep -i "router\|404\|error" || echo "  No relevant logs"
    ((ERRORS++))
elif [[ "${HTTP_CODE}" == "502" ]] || [[ "${HTTP_CODE}" == "503" ]]; then
    echo -e "${RED}✗${NC} ${HTTP_CODE} Bad Gateway - Backend unreachable"
    echo "  Checking Traefik logs..."
    docker logs traefik 2>&1 | tail -20 | grep -i "backend\|502\|503\|error" || echo "  No relevant logs"
    ((ERRORS++))
elif [[ "${HTTP_CODE}" == "000" ]]; then
    echo -e "${RED}✗${NC} Connection failed"
    echo "  Response: ${RESPONSE:0:200}"
    ((ERRORS++))
else
    echo -e "${YELLOW}⚠${NC} Unexpected HTTP ${HTTP_CODE}"
    echo "  Response: ${RESPONSE:0:200}"
    ((ERRORS++))
fi
echo ""

# 9. Check Traefik Logs for Errors
echo "9. Traefik Error Logs"
echo "----------------------------------------"
RECENT_ERRORS=$(docker logs traefik 2>&1 | tail -50 | grep -i "error\|warn\|fail" | head -10)
if [[ -n "${RECENT_ERRORS}" ]]; then
    echo -e "${YELLOW}⚠${NC} Recent errors/warnings:"
    echo "${RECENT_ERRORS}"
else
    echo -e "${GREEN}✓${NC} No recent errors"
fi
echo ""

# 10. Restart Traefik if needed
if [[ ${ERRORS} -gt 0 ]]; then
    echo "10. Attempting Fixes"
    echo "----------------------------------------"
    echo "Restarting Traefik to reload configuration..."
    cd /opt/traefik && docker compose restart
    sleep 5
    echo "Waiting for Traefik to be ready..."
    sleep 5
    
    # Test again
    echo -n "Re-testing https://aispector.exnada.com/health... "
    HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "000")
    if [[ "${HTTP_CODE}" == "200" ]]; then
        echo -e "${GREEN}✓${NC} Fixed! (HTTP 200)"
        ERRORS=0
    else
        echo -e "${RED}✗${NC} Still failing (HTTP ${HTTP_CODE})"
    fi
    echo ""
fi

# Summary
echo "============================================================================"
if [[ ${ERRORS} -eq 0 ]]; then
    echo -e "${GREEN}✓ Reverse proxy is working${NC}"
    echo ""
    echo "Final test:"
    curl -s -k -H "Host: aispector.exnada.com" https://localhost/health | head -5
else
    echo -e "${RED}✗ Reverse proxy has issues (${ERRORS} error(s))${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Check Traefik logs: docker logs traefik"
    echo "2. Check CoreDNS logs: docker logs coredns"
    echo "3. Verify backend is running: curl http://vega:8000/health"
    echo "4. Check configuration: cat /opt/traefik/dynamic.yml"
fi
echo "============================================================================"

exit ${ERRORS}
