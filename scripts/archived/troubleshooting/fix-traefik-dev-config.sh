#!/bin/bash
# Fix Traefik dynamic.yml configuration for dev.exnada.com
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Fixing Traefik Configuration for dev.exnada.com"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DYNAMIC_FILE="/opt/traefik/dynamic.yml"

if [[ ! -f "${DYNAMIC_FILE}" ]]; then
    echo -e "${RED}✗${NC} ${DYNAMIC_FILE} not found"
    exit 1
fi

# Backup
BACKUP_FILE="${DYNAMIC_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
echo "Creating backup: ${BACKUP_FILE}"
sudo cp "${DYNAMIC_FILE}" "${BACKUP_FILE}"
echo ""

# Check YAML syntax
echo "Checking YAML syntax..."
if ! python3 -c "import yaml; yaml.safe_load(open('${DYNAMIC_FILE}'))" 2>/dev/null; then
    echo -e "${YELLOW}⚠${NC} YAML syntax error detected"
    echo "Checking line 98..."
    sed -n '95,105p' "${DYNAMIC_FILE}" | cat -n
    echo ""
fi

# Show current service-dev configuration
echo "Current service-dev configuration:"
grep -A 10 "service-dev:" "${DYNAMIC_FILE}" | head -15
echo ""

# Test backend connectivity
echo "Testing backend options..."
if curl -s --max-time 5 http://rigel:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} rigel:8000 is reachable"
    BACKEND_URL="http://rigel:8000"
elif curl -s --max-time 5 http://localhost:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} localhost:8000 is reachable"
    BACKEND_URL="http://localhost:8000"
else
    echo -e "${RED}✗${NC} Neither rigel:8000 nor localhost:8000 is reachable"
    exit 1
fi

echo ""
echo "Using backend URL: ${BACKEND_URL}"
echo ""

# Fix the backend URL - replace any existing dev service URL
echo "Fixing backend URL in configuration..."
sudo sed -i.tmp "s|url:.*rigel.*8000|url: \"${BACKEND_URL}\"|g" "${DYNAMIC_FILE}"
sudo sed -i.tmp "s|url:.*100\.[0-9.]*:8000|url: \"${BACKEND_URL}\"|g" "${DYNAMIC_FILE}"

# Also ensure service-dev section is correct
# Check if the URL line exists in service-dev section
if ! grep -A 10 "service-dev:" "${DYNAMIC_FILE}" | grep -q "url:"; then
    echo "Adding URL to service-dev section..."
    # This is more complex - we'd need to parse YAML properly
    # For now, let's just ensure the URL is there
    echo -e "${YELLOW}⚠${NC} URL line not found in service-dev section - manual fix may be needed"
fi

# Validate YAML syntax again
echo ""
echo "Validating YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('${DYNAMIC_FILE}'))" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} YAML syntax is valid"
else
    echo -e "${RED}✗${NC} YAML syntax error still present"
    echo "Showing problematic area:"
    python3 -c "import yaml; yaml.safe_load(open('${DYNAMIC_FILE}'))" 2>&1 | head -5
    echo ""
    echo "Restoring backup..."
    sudo cp "${BACKUP_FILE}" "${DYNAMIC_FILE}"
    exit 1
fi

# Show updated configuration
echo ""
echo "Updated service-dev configuration:"
grep -A 10 "service-dev:" "${DYNAMIC_FILE}" | head -15
echo ""

# Restart Traefik
echo "Restarting Traefik..."
docker restart traefik
sleep 5

# Test
echo ""
echo "Testing dev.exnada.com route..."
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: dev.exnada.com" https://localhost/health 2>&1 || echo "000")
RESPONSE=$(curl -s -k --max-time 10 -H "Host: dev.exnada.com" https://localhost/health 2>&1 || echo "FAILED")

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓${NC} SUCCESS! dev.exnada.com is working (HTTP ${HTTP_CODE})"
    echo "Response: ${RESPONSE}"
elif [[ "${HTTP_CODE}" == "503" ]] || [[ "${HTTP_CODE}" == "502" ]]; then
    echo -e "${RED}✗${NC} Still getting ${HTTP_CODE} - Backend unreachable"
    echo "Check Traefik logs: docker logs traefik | tail -20"
    echo "Response: ${RESPONSE}"
else
    echo -e "${YELLOW}⚠${NC} Unexpected response (HTTP ${HTTP_CODE})"
    echo "Response: ${RESPONSE}"
fi

echo ""
echo "============================================================================"
echo "Configuration updated"
echo "Backup saved to: ${BACKUP_FILE}"
echo "============================================================================"
