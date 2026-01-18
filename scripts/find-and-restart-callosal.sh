#!/bin/bash
# Find and restart the callosal service on vega
# Run this on vega

set -euo pipefail

echo "============================================================================"
echo "Finding and Restarting Callosal Service (port 8001)"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Checking for Docker containers"
echo "----------------------------------------"
echo "All running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No containers running"
echo ""

echo "Containers with 'callosal' in name:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -i callosal || echo "No callosal containers found"
echo ""

echo "2. Checking systemd services"
echo "----------------------------------------"
echo "Services with 'callosal' in name:"
systemctl list-units --all | grep -i callosal || echo "No callosal systemd services found"
echo ""

echo "3. Checking processes"
echo "----------------------------------------"
echo "Processes with 'callosal' or '8001' in command:"
ps aux | grep -E "callosal|8001" | grep -v grep || echo "No matching processes found"
echo ""

echo "4. Checking for service files"
echo "----------------------------------------"
echo "Systemd service files:"
find /etc/systemd/system -name "*callosal*" 2>/dev/null || echo "No callosal systemd service files found"
echo ""

echo "Docker compose files:"
find /home -name "*callosal*" -name "docker-compose.yml" 2>/dev/null | head -5 || echo "No callosal docker-compose files found in /home"
find /opt -name "*callosal*" -name "docker-compose.yml" 2>/dev/null | head -5 || echo "No callosal docker-compose files found in /opt"
echo ""

echo "5. Checking recent systemd logs"
echo "----------------------------------------"
echo "Recent systemd messages about callosal or port 8001:"
journalctl -u "*callosal*" --no-pager -n 20 2>/dev/null || echo "No callosal service logs found"
echo ""

echo "6. Checking Docker logs"
echo "----------------------------------------"
echo "Recent Docker container logs (last 20 lines of each):"
for container in $(docker ps -a --format "{{.Names}}" | grep -i callosal); do
    echo "--- Logs for $container ---"
    docker logs --tail 20 "$container" 2>&1 || echo "Could not get logs"
    echo ""
done

echo "============================================================================"
echo "Next Steps"
echo "============================================================================"
echo "If you found a Docker container:"
echo "  docker start <container-name>"
echo ""
echo "If you found a systemd service:"
echo "  sudo systemctl start <service-name>"
echo ""
echo "If you found a docker-compose file:"
echo "  cd <directory> && docker compose up -d"
echo ""
echo "If nothing was found, the service may need to be deployed/configured."
echo "============================================================================"
