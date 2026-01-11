#!/bin/bash
# Docker-based certificate issuance script
# This script runs the certificate issuance in a containerized environment
# Usage: ./run-cert-issuance-docker.sh [staging|production]

set -euo pipefail

CA_SERVER="${1:-staging}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if we're on the target host (rigel)
if ! ssh -o ConnectTimeout=5 rigel "echo 'Connected'" &>/dev/null; then
    log_info "This script should be run on rigel, or via SSH to rigel"
    log_info "To run on rigel directly, use: sudo /path/to/run-cert-issuance.sh"
    log_info "To run via SSH: ssh rigel 'sudo bash -s' < scripts/run-cert-issuance.sh"
    exit 1
fi

log_info "Running certificate issuance on rigel..."
log_info "CA Server: ${CA_SERVER}"

# Copy scripts to rigel
log_info "Copying scripts to rigel..."
scp "${SCRIPT_DIR}/run-cert-issuance.sh" rigel:/tmp/run-cert-issuance.sh
ssh rigel "chmod +x /tmp/run-cert-issuance.sh"

# Execute on rigel
log_info "Executing certificate issuance..."
ssh rigel "sudo /tmp/run-cert-issuance.sh ${CA_SERVER}"

log_info "Done!"
