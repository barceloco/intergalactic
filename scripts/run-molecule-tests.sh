#!/bin/bash
# Run Molecule tests for all roles (containerized)
# Usage: ./scripts/run-molecule-tests.sh [role-name|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

ROLE="${1:-all}"
IMAGE="intergalactic-ansible-testing:latest"

# Build testing image (quiet unless it fails)
echo "Building testing container..."
if ! docker build -t "${IMAGE}" -f docker/ansible-runner/Dockerfile.testing docker/ansible-runner > /dev/null 2>&1; then
    echo "ERROR: Failed to build testing container"
    docker build -t "${IMAGE}" -f docker/ansible-runner/Dockerfile.testing docker/ansible-runner
    exit 1
fi

# Check for Docker socket (required for Molecule)
if [ ! -S /var/run/docker.sock ]; then
    echo "ERROR: Docker socket not found. Molecule requires access to host Docker."
    echo "  On macOS: Docker Desktop must be running"
    echo "  On Linux: Ensure Docker socket is accessible"
    exit 1
fi

echo "============================================================================"
echo "Molecule Role Testing (Containerized)"
echo "============================================================================"
echo ""

ROLES_WITH_MOLECULE=(
    "docker_deploy"
    "internal_dns"
    "edge_ingress"
    "firewall_nftables"
)

if [ "$ROLE" != "all" ]; then
    if [[ ! " ${ROLES_WITH_MOLECULE[@]} " =~ " ${ROLE} " ]]; then
        echo "ERROR: Role '${ROLE}' does not have Molecule tests."
        echo "Available roles: ${ROLES_WITH_MOLECULE[*]}"
        exit 1
    fi
    ROLES_TO_TEST=("$ROLE")
else
    ROLES_TO_TEST=("${ROLES_WITH_MOLECULE[@]}")
fi

ERRORS=0
PASSED=0

for role in "${ROLES_TO_TEST[@]}"; do
    echo "Testing role: ${role}"
    echo "----------------------------------------"
    
    ROLE_DIR="ansible/roles/${role}"
    if [ ! -d "${ROLE_DIR}/molecule" ]; then
        echo "⚠ Skipping ${role} (no molecule directory)"
        continue
    fi
    
    # Run Molecule in container with Docker socket access
    if docker run --rm -it \
        -v "${SCRIPT_DIR}:/repo" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -w "/repo/${ROLE_DIR}" \
        "${IMAGE}" \
        molecule test; then
        echo "✓ ${role}: PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "✗ ${role}: FAILED"
        ERRORS=$((ERRORS + 1))
    fi
    echo ""
done

echo "============================================================================"
echo "Results: ${PASSED} passed, ${ERRORS} failed"
echo "============================================================================"

if [ $ERRORS -eq 0 ]; then
    exit 0
else
    exit 1
fi
