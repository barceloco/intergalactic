#!/usr/bin/env bash
# Run intergalactic scripts on rigel via SSH
# Usage: ./scripts/run-on-rigel.sh <script-name> [script-args...]
# Example: ./scripts/run-on-rigel.sh check-dev-exnada-traefik.sh
# Example: ./scripts/run-on-rigel.sh create-traefik-dev-config.sh

set -euo pipefail

# Configuration
HOST="${RIGEL_HOST:-rigel}"
SSH_KEY="${SSH_KEY:-~/.ssh/intergalactic_ansible}"
SSH_USER="${RIGEL_USER:-ansible}"
REMOTE_SCRIPT_DIR="${REMOTE_SCRIPT_DIR:-/tmp/intergalactic-scripts}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if command provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <script-name-or-command> [args...]"
    echo ""
    echo "Examples:"
    echo "  $0 check-dev-exnada-traefik.sh"
    echo "  $0 create-traefik-dev-config.sh"
    echo "  $0 'dpkg -l | grep dnsutils'  # Raw command (use quotes)"
    echo ""
    echo "Available scripts:"
    ls -1 scripts/*.sh | sed 's|scripts/||' | grep -v "run-on-rigel.sh\|run-ansible.sh" | head -20
    exit 1
fi

COMMAND="$1"
shift
SCRIPT_ARGS="$@"

# Get absolute path to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/${COMMAND}"

# Check if it's a script file or a raw command
if [[ -f "${SCRIPT_PATH}" ]]; then
    # It's a script file
    SCRIPT_NAME="${COMMAND}"
    IS_SCRIPT=true
else
    # It's a raw command - execute directly
    IS_SCRIPT=false
    RAW_COMMAND="${COMMAND}"
    if [[ -n "${SCRIPT_ARGS}" ]]; then
        RAW_COMMAND="${RAW_COMMAND} ${SCRIPT_ARGS}"
    fi
fi

# Expand SSH key path
SSH_KEY_EXPANDED="${SSH_KEY/#\~/$HOME}"

# Check if SSH key exists
if [[ ! -f "${SSH_KEY_EXPANDED}" ]]; then
    echo -e "${YELLOW}⚠${NC} SSH key not found: ${SSH_KEY_EXPANDED}"
    echo "Set SSH_KEY environment variable or create the key"
    exit 1
fi

echo "============================================================================"
if [[ "${IS_SCRIPT}" == "true" ]]; then
    echo "Running ${SCRIPT_NAME} on ${HOST}"
else
    echo "Executing command on ${HOST}"
fi
echo "============================================================================"
echo ""
echo "Host: ${HOST}"
echo "User: ${SSH_USER}"
if [[ "${IS_SCRIPT}" == "true" ]]; then
    echo "Script: ${SCRIPT_NAME}"
    if [[ -n "${SCRIPT_ARGS}" ]]; then
        echo "Args: ${SCRIPT_ARGS}"
    fi
else
    echo "Command: ${RAW_COMMAND}"
fi
echo ""

# Test SSH connection
echo "Testing SSH connection..."
if ! ssh -i "${SSH_KEY_EXPANDED}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SSH_USER}@${HOST}" "echo 'Connection successful'" >/dev/null 2>&1; then
    echo -e "${RED}✗${NC} Cannot connect to ${SSH_USER}@${HOST}"
    echo "Check:"
    echo "  1. SSH key is correct: ${SSH_KEY_EXPANDED}"
    echo "  2. Host is reachable: ping ${HOST}"
    echo "  3. SSH access is configured"
    exit 1
fi
echo -e "${GREEN}✓${NC} SSH connection successful"
echo ""

# Run the script or command
echo "============================================================================"
if [[ "${IS_SCRIPT}" == "true" ]]; then
    echo "Executing script on ${HOST}..."
    echo "============================================================================"
    echo ""
    
    # Create remote script directory
    echo "Setting up remote script directory..."
    ssh -i "${SSH_KEY_EXPANDED}" "${SSH_USER}@${HOST}" "mkdir -p ${REMOTE_SCRIPT_DIR}" >/dev/null 2>&1
    
    # Copy script to remote host
    REMOTE_SCRIPT_PATH="${REMOTE_SCRIPT_DIR}/${SCRIPT_NAME}"
    echo "Copying script to ${HOST}:${REMOTE_SCRIPT_PATH}..."
    scp -i "${SSH_KEY_EXPANDED}" -q "${SCRIPT_PATH}" "${SSH_USER}@${HOST}:${REMOTE_SCRIPT_PATH}"
    
    # Make script executable
    ssh -i "${SSH_KEY_EXPANDED}" "${SSH_USER}@${HOST}" "chmod +x ${REMOTE_SCRIPT_PATH}" >/dev/null 2>&1
    
    echo -e "${GREEN}✓${NC} Script copied and made executable"
    echo ""
    
    # Run script and capture exit code
    set +e
    ssh -i "${SSH_KEY_EXPANDED}" -t "${SSH_USER}@${HOST}" "${REMOTE_SCRIPT_PATH} ${SCRIPT_ARGS}"
    EXIT_CODE=$?
    set -e
else
    echo "Executing command on ${HOST}..."
    echo "============================================================================"
    echo ""
    
    # Run command directly and capture exit code
    set +e
    ssh -i "${SSH_KEY_EXPANDED}" -t "${SSH_USER}@${HOST}" "${RAW_COMMAND}"
    EXIT_CODE=$?
    set -e
fi

echo ""
echo "============================================================================"
if [[ ${EXIT_CODE} -eq 0 ]]; then
    echo -e "${GREEN}✓${NC} Script completed successfully"
else
    echo -e "${RED}✗${NC} Script exited with code ${EXIT_CODE}"
fi
echo "============================================================================"

# Optionally clean up (comment out if you want to keep scripts on remote)
# ssh -i "${SSH_KEY_EXPANDED}" "${SSH_USER}@${HOST}" "rm -f ${REMOTE_SCRIPT_PATH}" >/dev/null 2>&1

exit ${EXIT_CODE}
