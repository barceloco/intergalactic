#!/bin/bash
# Inspect and fix Traefik dynamic.yml - shows the file and fixes issues
# Run this on rigel

set -euo pipefail

DYNAMIC_FILE="/opt/traefik/dynamic.yml"

echo "============================================================================"
echo "Inspecting Traefik Configuration"
echo "============================================================================"
echo ""

if [[ ! -f "${DYNAMIC_FILE}" ]]; then
    echo "ERROR: ${DYNAMIC_FILE} not found"
    exit 1
fi

echo "Full file content:"
echo "----------------------------------------"
cat "${DYNAMIC_FILE}"
echo ""

echo "Checking YAML syntax..."
echo "----------------------------------------"
if python3 -c "import yaml; yaml.safe_load(open('${DYNAMIC_FILE}'))" 2>&1; then
    echo "✓ YAML syntax is valid"
else
    echo "✗ YAML syntax error:"
    python3 -c "import yaml; yaml.safe_load(open('${DYNAMIC_FILE}'))" 2>&1
    echo ""
    echo "Showing lines around error (line 98):"
    sed -n '90,105p' "${DYNAMIC_FILE}" | cat -n
fi
