#!/bin/bash
# Run linting checks on Ansible codebase (containerized)
# Usage: ./scripts/run-linting.sh [ansible-lint|yamllint|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

MODE="${1:-all}"
IMAGE="intergalactic-ansible-testing:latest"

# Build testing image (quiet unless it fails)
echo "Building testing container..."
if ! docker build -t "${IMAGE}" -f docker/ansible-runner/Dockerfile.testing docker/ansible-runner > /dev/null 2>&1; then
    echo "ERROR: Failed to build testing container"
    docker build -t "${IMAGE}" -f docker/ansible-runner/Dockerfile.testing docker/ansible-runner
    exit 1
fi

echo "============================================================================"
echo "Ansible Linting (Containerized)"
echo "============================================================================"
echo ""

ERRORS=0

if [ "$MODE" = "all" ] || [ "$MODE" = "ansible-lint" ]; then
    echo "Running ansible-lint..."
    if docker run --rm -v "${SCRIPT_DIR}:/repo" "${IMAGE}" \
        ansible-lint ansible/ --exclude ansible/molecule/ --exclude ansible/.cache/; then
        echo "✓ ansible-lint: PASSED"
    else
        echo "✗ ansible-lint: FAILED"
        ERRORS=$((ERRORS + 1))
    fi
    echo ""
fi

if [ "$MODE" = "all" ] || [ "$MODE" = "yamllint" ]; then
    echo "Running yamllint..."
    if docker run --rm -v "${SCRIPT_DIR}:/repo" "${IMAGE}" \
        yamllint -c .yamllint ansible/; then
        echo "✓ yamllint: PASSED"
    else
        echo "✗ yamllint: FAILED"
        ERRORS=$((ERRORS + 1))
    fi
    echo ""
fi

echo "============================================================================"
if [ $ERRORS -eq 0 ]; then
    echo "✓ All linting checks passed!"
    echo "============================================================================"
    exit 0
else
    echo "✗ Linting failed: ${ERRORS} error(s)"
    echo "============================================================================"
    exit 1
fi
