#!/bin/bash
# Quick diagnostic and fix script for services after reboot
# Run this on rigel to check and start services

set -euo pipefail

echo "============================================================================"
echo "Post-Reboot Service Check"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Check Docker service
echo "1. Docker Service Status"
echo "----------------------------------------"
if systemctl is-active --quiet docker; then
    echo -e "${GREEN}✓${NC} Docker service is running"
else
    echo -e "${RED}✗${NC} Docker service is not running"
    echo "Starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
    sleep 2
fi
echo ""

# 2. Check Tailscale
echo "2. Tailscale Status"
echo "----------------------------------------"
if command -v tailscale &>/dev/null; then
    if tailscale status &>/dev/null; then
        echo -e "${GREEN}✓${NC} Tailscale is connected"
        tailscale status | head -3
    else
        echo -e "${RED}✗${NC} Tailscale is not connected"
        echo "Run: sudo tailscale up"
    fi
else
    echo -e "${YELLOW}⚠${NC} Tailscale not found"
fi
echo ""

# 3. Check CoreDNS container
echo "3. CoreDNS Container Status"
echo "----------------------------------------"
if docker ps | grep -q coredns; then
    echo -e "${GREEN}✓${NC} CoreDNS is running"
    docker ps | grep coredns
else
    echo -e "${RED}✗${NC} CoreDNS is not running"
    if [[ -f /opt/coredns/docker-compose.yml ]]; then
        echo "Starting CoreDNS..."
        cd /opt/coredns && docker compose up -d
        sleep 2
        if docker ps | grep -q coredns; then
            echo -e "${GREEN}✓${NC} CoreDNS started successfully"
        else
            echo -e "${RED}✗${NC} Failed to start CoreDNS"
            echo "Check logs: docker logs coredns"
        fi
    else
        echo -e "${RED}✗${NC} CoreDNS compose file not found at /opt/coredns/docker-compose.yml"
    fi
fi
echo ""

# 4. Check Traefik container
echo "4. Traefik Container Status"
echo "----------------------------------------"
if docker ps | grep -q traefik; then
    echo -e "${GREEN}✓${NC} Traefik is running"
    docker ps | grep traefik
else
    echo -e "${RED}✗${NC} Traefik is not running"
    if [[ -f /opt/traefik/docker-compose.yml ]]; then
        echo "Starting Traefik..."
        cd /opt/traefik && docker compose up -d
        sleep 2
        if docker ps | grep -q traefik; then
            echo -e "${GREEN}✓${NC} Traefik started successfully"
        else
            echo -e "${RED}✗${NC} Failed to start Traefik"
            echo "Check logs: docker logs traefik"
        fi
    else
        echo -e "${RED}✗${NC} Traefik compose file not found at /opt/traefik/docker-compose.yml"
    fi
fi
echo ""

# 5. Check all containers
echo "5. All Running Containers"
echo "----------------------------------------"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No containers running"
echo ""

# 6. Test connectivity
echo "6. Testing Backend Connectivity"
echo "----------------------------------------"
echo -n "Testing vega:8000/health... "
if curl -s --max-time 5 http://vega:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable"
else
    echo -e "${RED}✗${NC} Not reachable"
    echo "  This might be normal if vega is also rebooting"
fi
echo ""

echo "============================================================================"
echo "Diagnostic complete"
echo "============================================================================"
echo ""
echo "If services are still not working, check logs:"
echo "  docker logs traefik"
echo "  docker logs coredns"
echo "  sudo journalctl -u docker -n 50"
echo ""
