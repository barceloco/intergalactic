#!/bin/bash
# Run all tests (containerized)
# Usage: ./scripts/run-all-tests.sh [--skip-lint] [--skip-molecule] [--skip-testinfra]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

SKIP_LINT=false
SKIP_MOLECULE=false
SKIP_TESTINFRA=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-lint)
            SKIP_LINT=true
            shift
            ;;
        --skip-molecule)
            SKIP_MOLECULE=true
            shift
            ;;
        --skip-testinfra)
            SKIP_TESTINFRA=true
            shift
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--skip-lint] [--skip-molecule] [--skip-testinfra]"
            exit 1
            ;;
    esac
done

echo "============================================================================"
echo "Running All Tests (Containerized)"
echo "============================================================================"
echo ""

ERRORS=0

# Phase 1: Linting
if [ "$SKIP_LINT" = false ]; then
    echo "Phase 1: Linting and Syntax Checks"
    echo "----------------------------------------"
    
    if ./scripts/run-linting.sh; then
        echo "✓ Linting: PASSED"
    else
        echo "✗ Linting: FAILED"
        ERRORS=$((ERRORS + 1))
    fi
    echo ""
    
    if ./scripts/validate-playbooks.sh; then
        echo "✓ Syntax Check: PASSED"
    else
        echo "✗ Syntax Check: FAILED"
        ERRORS=$((ERRORS + 1))
    fi
    echo ""
else
    echo "⚠ Skipping linting (--skip-lint)"
    echo ""
fi

# Phase 2: Molecule
if [ "$SKIP_MOLECULE" = false ]; then
    echo "Phase 2: Molecule Role Tests"
    echo "----------------------------------------"
    
    if ./scripts/run-molecule-tests.sh; then
        echo "✓ Molecule: PASSED"
    else
        echo "✗ Molecule: FAILED"
        ERRORS=$((ERRORS + 1))
    fi
    echo ""
else
    echo "⚠ Skipping Molecule (--skip-molecule)"
    echo ""
fi

# Phase 3: Testinfra
if [ "$SKIP_TESTINFRA" = false ]; then
    echo "Phase 3: Testinfra Production Tests"
    echo "----------------------------------------"
    echo "⚠ Testinfra requires SSH access to production hosts"
    echo "  Run manually with Docker:"
    echo ""
    echo "    docker build -t intergalactic-ansible-testing:latest \\"
    echo "      -f docker/ansible-runner/Dockerfile.testing \\"
    echo "      docker/ansible-runner"
    echo ""
    echo "    docker run --rm -it \\"
    echo "      -v \$(pwd):/repo \\"
    echo "      -v \$HOME/.ssh:/root/.ssh:ro \\"
    echo "      intergalactic-ansible-testing:latest \\"
    echo "      pytest tests/testinfra/ \\"
    echo "        --hosts=ansible://rigel \\"
    echo "        --ansible-inventory=ansible/inventories/prod/hosts.yml \\"
    echo "        -v"
    echo ""
else
    echo "⚠ Skipping Testinfra (--skip-testinfra)"
    echo ""
fi

echo "============================================================================"
if [ $ERRORS -eq 0 ]; then
    echo "✓ All automated tests passed!"
    echo "============================================================================"
    exit 0
else
    echo "✗ Tests failed: ${ERRORS} phase(s) failed"
    echo "============================================================================"
    exit 1
fi
