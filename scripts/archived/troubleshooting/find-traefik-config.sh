#!/bin/bash
# Find Traefik configuration files
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Finding Traefik Configuration"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Traefik Container Details"
echo "----------------------------------------"
docker inspect traefik --format 'Container Name: {{.Name}}' 2>/dev/null || echo "Could not inspect traefik"
echo ""

echo "2. Traefik Container Volumes/Mounts"
echo "----------------------------------------"
echo "Volume mounts:"
docker inspect traefik --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{"\n"}}{{end}}' 2>/dev/null || echo "Could not inspect mounts"
echo ""

echo "3. Traefik Container Command"
echo "----------------------------------------"
docker inspect traefik --format 'Command: {{.Config.Cmd}}' 2>/dev/null
docker inspect traefik --format 'Args: {{range .Args}}{{.}} {{end}}' 2>/dev/null
echo ""

echo "4. Checking Common Config Locations"
echo "----------------------------------------"
for path in "/opt/traefik" "/etc/traefik" "/var/lib/traefik" "/traefik"; do
    if [[ -d "${path}" ]]; then
        echo -e "${GREEN}✓${NC} ${path} exists"
        ls -la "${path}" 2>/dev/null | head -10
    else
        echo -e "${RED}✗${NC} ${path} does not exist"
    fi
    echo ""
done

echo "5. Searching for dynamic.yml"
echo "----------------------------------------"
find /opt /etc /var/lib -name "dynamic.yml" -type f 2>/dev/null | head -10 || echo "No dynamic.yml found"
echo ""

echo "6. Searching for traefik.yml"
echo "----------------------------------------"
find /opt /etc /var/lib -name "traefik.yml" -type f 2>/dev/null | head -10 || echo "No traefik.yml found"
echo ""

echo "7. Traefik Container Logs (config-related)"
echo "----------------------------------------"
echo "Recent logs mentioning config:"
docker logs traefik 2>&1 | grep -i "config\|file\|dynamic\|error" | tail -20 || echo "No config-related logs"
echo ""

echo "8. Checking if Traefik is using file provider"
echo "----------------------------------------"
docker logs traefik 2>&1 | grep -i "providers\|file\|dynamic" | tail -10 || echo "No provider info in logs"
echo ""

echo "============================================================================"
echo "Next Steps"
echo "============================================================================"
echo "If /opt/traefik doesn't exist or is empty:"
echo "  1. Traefik may not have been deployed via Ansible"
echo "  2. Run the edge_ingress Ansible role to deploy Traefik properly"
echo "  3. Or manually create the config directory and files"
echo ""
echo "If config exists elsewhere:"
echo "  - Update the Ansible role to use that location"
echo "  - Or create a symlink"
echo "============================================================================"
