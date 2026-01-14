#!/bin/bash
# Validate all Ansible playbooks (containerized)
# Usage: ./scripts/validate-playbooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

IMAGE="intergalactic-ansible-testing:latest"

# Build testing image (quiet unless it fails)
echo "Building testing container..."
if ! docker build -t "${IMAGE}" -f docker/ansible-runner/Dockerfile.testing docker/ansible-runner > /dev/null 2>&1; then
    echo "ERROR: Failed to build testing container"
    docker build -t "${IMAGE}" -f docker/ansible-runner/Dockerfile.testing docker/ansible-runner
    exit 1
fi

echo "============================================================================"
echo "Ansible Playbook Validation (Containerized)"
echo "============================================================================"
echo ""

# Find all playbook files
PLAYBOOKS=$(find ansible/playbooks -name "*.yml" -type f | sort)

if [ -z "$PLAYBOOKS" ]; then
    echo "No playbooks found in ansible/playbooks/"
    exit 1
fi

echo "Found $(echo "$PLAYBOOKS" | wc -l) playbook(s) to validate"
echo ""

ERRORS=0
WARNINGS=0

for playbook in $PLAYBOOKS; do
    playbook_rel="${playbook#ansible/}"
    echo "Validating: $playbook_rel"
    
    # Syntax check using container
    if docker run --rm -v "${SCRIPT_DIR}:/repo" "${IMAGE}" \
        ansible-playbook --syntax-check "ansible/${playbook_rel}" > /dev/null 2>&1; then
        echo "  ✓ Syntax: OK"
    else
        echo "  ✗ Syntax: FAILED"
        docker run --rm -v "${SCRIPT_DIR}:/repo" "${IMAGE}" \
            ansible-playbook --syntax-check "ansible/${playbook_rel}" 2>&1 | sed 's/^/    /'
        ERRORS=$((ERRORS + 1))
    fi
    
    # Check for common issues (using host grep, faster)
    if grep -q "{{.*}}" "$playbook" && ! grep -q "when:" "$playbook"; then
        echo "  ⚠ Warning: Contains Jinja2 templates but no conditional logic"
        WARNINGS=$((WARNINGS + 1))
    fi
done

echo ""
echo "============================================================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✓ All playbooks validated successfully!"
    echo "============================================================================"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo "✓ All playbooks passed syntax check (${WARNINGS} warning(s))"
    echo "============================================================================"
    exit 0
else
    echo "✗ Validation failed: ${ERRORS} error(s), ${WARNINGS} warning(s)"
    echo "============================================================================"
    exit 1
fi
