#!/bin/bash
# Check infrastructure services (Traefik, CoreDNS) status
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Checking Infrastructure Services"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Docker Containers Status"
echo "----------------------------------------"
echo "All containers:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20
echo ""

echo "2. Traefik Status"
echo "----------------------------------------"
if docker ps -a --format "{{.Names}}" | grep -q "^traefik$"; then
    echo "Traefik container exists:"
    docker ps -a --filter "name=traefik" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    if docker ps --format "{{.Names}}" | grep -q "^traefik$"; then
        echo -e "${GREEN}✓${NC} Traefik is running"
        echo "Recent logs:"
        docker logs traefik 2>&1 | tail -10
    else
        echo -e "${RED}✗${NC} Traefik is stopped"
        echo "Attempting to start..."
        docker start traefik || echo "Failed to start"
        sleep 3
        if docker ps --format "{{.Names}}" | grep -q "^traefik$"; then
            echo -e "${GREEN}✓${NC} Traefik started"
        else
            echo -e "${RED}✗${NC} Failed to start Traefik"
            echo "Logs:"
            docker logs traefik 2>&1 | tail -20
        fi
    fi
else
    echo -e "${RED}✗${NC} Traefik container does not exist"
    echo "Traefik should be deployed via Ansible edge_ingress role"
    echo "Check if /opt/traefik directory exists:"
    ls -la /opt/traefik 2>/dev/null || echo "  /opt/traefik does not exist"
fi
echo ""

echo "3. CoreDNS Status"
echo "----------------------------------------"
if docker ps -a --format "{{.Names}}" | grep -q "^coredns$"; then
    echo "CoreDNS container exists:"
    docker ps -a --filter "name=coredns" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    if docker ps --format "{{.Names}}" | grep -q "^coredns$"; then
        echo -e "${GREEN}✓${NC} CoreDNS is running"
        echo "Testing DNS resolution:"
        dig @127.0.0.1 dev.exnada.com +short +timeout=2 2>&1 || echo "DNS query failed"
    else
        echo -e "${RED}✗${NC} CoreDNS is stopped"
        echo "Attempting to start..."
        docker start coredns || echo "Failed to start"
        sleep 2
        if docker ps --format "{{.Names}}" | grep -q "^coredns$"; then
            echo -e "${GREEN}✓${NC} CoreDNS started"
        else
            echo -e "${RED}✗${NC} Failed to start CoreDNS"
            echo "Logs:"
            docker logs coredns 2>&1 | tail -20
        fi
    fi
else
    echo -e "${RED}✗${NC} CoreDNS container does not exist"
    echo "CoreDNS should be deployed via Ansible internal_dns role"
    echo "Check if /opt/coredns directory exists:"
    ls -la /opt/coredns 2>/dev/null || echo "  /opt/coredns does not exist"
fi
echo ""

echo "4. Systemd Services"
echo "----------------------------------------"
echo "Checking systemd services:"
systemctl is-active traefik.service 2>/dev/null && echo -e "${GREEN}✓${NC} traefik.service is active" || echo -e "${RED}✗${NC} traefik.service is not active"
systemctl is-active coredns.service 2>/dev/null && echo -e "${GREEN}✓${NC} coredns.service is active" || echo -e "${RED}✗${NC} coredns.service is not active"
echo ""

echo "5. Port 8000 Binding"
echo "----------------------------------------"
echo "Checking what's listening on port 8000:"
if command -v ss >/dev/null 2>&1; then
    ss -tlnp | grep :8000 || echo "Nothing listening on port 8000"
else
    netstat -tlnp 2>/dev/null | grep :8000 || echo "Nothing listening on port 8000"
fi
echo ""

echo "Checking aispector-api container network:"
if docker ps --format "{{.Names}}" | grep -q "aispector-api"; then
    echo "Container IP addresses:"
    docker inspect aispector-api --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}}: {{$value.IPAddress}}{{end}}' 2>/dev/null || echo "Could not inspect"
    echo ""
    echo "Port bindings:"
    docker inspect aispector-api --format '{{json .HostConfig.PortBindings}}' 2>/dev/null | python3 -m json.tool 2>/dev/null || docker inspect aispector-api --format '{{.HostConfig.PortBindings}}' 2>/dev/null
    echo ""
    echo "Network mode:"
    docker inspect aispector-api --format '{{.HostConfig.NetworkMode}}' 2>/dev/null
fi
echo ""

echo "6. Testing Service Accessibility"
echo "----------------------------------------"
echo "Testing rigel:8000 (via DNS):"
curl -s --max-time 5 http://rigel:8000/health 2>&1 | head -1 || echo "Failed"
echo ""

echo "Testing localhost:8000:"
curl -s --max-time 5 http://localhost:8000/health 2>&1 | head -1 || echo "Failed"
echo ""

echo "Testing 127.0.0.1:8000:"
curl -s --max-time 5 http://127.0.0.1:8000/health 2>&1 | head -1 || echo "Failed"
echo ""

# Get rigel's IP
RIGEL_IP=$(getent hosts rigel 2>/dev/null | awk '{print $1}' | head -1)
if [[ -n "${RIGEL_IP}" ]]; then
    echo "Testing ${RIGEL_IP}:8000 (rigel's IP):"
    curl -s --max-time 5 http://${RIGEL_IP}:8000/health 2>&1 | head -1 || echo "Failed"
fi
echo ""

echo "============================================================================"
echo "Summary"
echo "============================================================================"
echo "If Traefik/CoreDNS are not running:"
echo "  1. Start them: docker start traefik coredns"
echo "  2. Or restart systemd services: sudo systemctl restart traefik coredns"
echo "  3. Or redeploy via Ansible playbook"
echo ""
echo "If localhost:8000 doesn't work but rigel:8000 does:"
echo "  - Container might be bound to a specific interface"
echo "  - Traefik should use 'rigel:8000' instead of 'localhost:8000'"
echo "  - Or ensure container binds to 0.0.0.0:8000"
echo "============================================================================"
