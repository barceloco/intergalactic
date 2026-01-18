#!/bin/bash
# Emergency script to restore Docker containers on vega
# Run this on vega

set -euo pipefail

echo "============================================================================"
echo "Emergency Container Restoration for vega"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Check Docker daemon status"
echo "----------------------------------------"
if systemctl is-active --quiet docker; then
    echo -e "${GREEN}✓${NC} Docker daemon is running"
else
    echo -e "${RED}✗${NC} Docker daemon is NOT running!"
    echo "Starting Docker daemon..."
    sudo systemctl start docker
    sleep 2
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✓${NC} Docker daemon started"
    else
        echo -e "${RED}✗${NC} Failed to start Docker daemon"
        exit 1
    fi
fi
echo ""

echo "2. Check all containers (including stopped)"
echo "----------------------------------------"
echo "All containers:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}" || echo "No containers found"
echo ""

echo "3. Find docker-compose files"
echo "----------------------------------------"
echo "Searching for docker-compose.yml files..."
find /opt /home -name "docker-compose.yml" -type f 2>/dev/null | head -10
echo ""

echo "4. Check systemd services that manage containers"
echo "----------------------------------------"
echo "Systemd services that might manage containers:"
systemctl list-units --type=service --all | grep -E "coredns|traefik|docker" || echo "No matching services found"
echo ""

echo "5. Attempt to restart systemd-managed containers"
echo "----------------------------------------"
for service in coredns traefik; do
    if systemctl list-units --all | grep -q "${service}.service"; then
        echo "Restarting ${service}..."
        sudo systemctl restart "${service}" 2>/dev/null && echo -e "${GREEN}✓${NC} ${service} restarted" || echo -e "${YELLOW}⚠${NC} ${service} restart failed or not needed"
    fi
done
echo ""

echo "6. Check for containers that should auto-start"
echo "----------------------------------------"
echo "Containers with restart policies:"
docker ps -a --format "{{.Names}}\t{{.RestartPolicy}}" | grep -v "no" || echo "No containers with restart policies found"
echo ""

echo "7. Attempt to start stopped containers"
echo "----------------------------------------"
STOPPED=$(docker ps -a --filter "status=exited" --format "{{.Names}}")
if [[ -n "${STOPPED}" ]]; then
    echo "Found stopped containers:"
    echo "${STOPPED}"
    echo ""
    echo "Attempting to start them..."
    while IFS= read -r container; do
        if [[ -n "${container}" ]]; then
            echo -n "Starting ${container}... "
            docker start "${container}" 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC} Failed"
        fi
    done <<< "${STOPPED}"
else
    echo "No stopped containers found"
fi
echo ""

echo "8. Check Docker networking"
echo "----------------------------------------"
echo "Docker networks:"
docker network ls
echo ""

echo "9. Check firewall rules affecting Docker"
echo "----------------------------------------"
echo "Checking if firewall is blocking Docker networking..."
if sudo nft list ruleset 2>/dev/null | grep -q "FORWARD.*drop"; then
    echo -e "${YELLOW}⚠${NC} Firewall FORWARD chain is set to DROP"
    echo "  This might block Docker container networking!"
    echo "  Docker containers need FORWARD rules to communicate"
fi
echo ""

echo "============================================================================"
echo "Summary"
echo "============================================================================"
echo "Current container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No containers running"
echo ""
echo "If containers are still not running:"
echo "  1. Check logs: docker logs <container-name>"
echo "  2. Check docker-compose files and restart: cd <dir> && docker compose up -d"
echo "  3. Check systemd services: systemctl status <service-name>"
echo "============================================================================"
