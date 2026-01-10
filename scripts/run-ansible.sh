#!/usr/bin/env bash
set -euo pipefail

# Three-phase infrastructure deployment script
# Usage:
#   ./scripts/run-ansible.sh prod rigel bootstrap      # Phase 1: Initial access setup
#   ./scripts/run-ansible.sh prod rigel foundation    # Phase 2: Network + security
#   ./scripts/run-ansible.sh prod rigel production    # Phase 3: Application services

ENV_NAME="${1:-prod}"
HOST="${2:-rigel}"
PHASE="${3:-production}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="intergalactic-ansible-runner:latest"

docker build -t "${IMAGE}" "${ROOT_DIR}/docker/ansible-runner"

# Determine inventory, playbook, and SSH user based on phase
case "${PHASE}" in
  bootstrap)
    INVENTORY_FILE="inventories/${ENV_NAME}/hosts-bootstrap.yml"
    PLAYBOOK="${HOST}-bootstrap"
    SSH_USER="armand"
    echo "============================================================================"
    echo "Phase 1: BOOTSTRAP - Initial Access Setup"
    echo "============================================================================"
    echo "Connection: Local IP address"
    echo "User: ${SSH_USER}"
    echo "Purpose: Create ansible user, disable password auth, set up SSH keys"
    echo "============================================================================"
    ;;
  foundation)
    INVENTORY_FILE="inventories/${ENV_NAME}/hosts-foundation.yml"
    PLAYBOOK="${HOST}-foundation"
    SSH_USER="ansible"
    echo "============================================================================"
    echo "Phase 2: FOUNDATION - Network + Security + Base Infrastructure"
    echo "============================================================================"
    echo "Connection: Local IP address (may require local network)"
    echo "User: ${SSH_USER}"
    echo "Purpose: Tailscale, SSH hardening, firewall, Docker, monitoring"
    echo "============================================================================"
    ;;
  production)
    INVENTORY_FILE="inventories/${ENV_NAME}/hosts.yml"
    PLAYBOOK="${HOST}-production"
    SSH_USER="ansible"
    echo "============================================================================"
    echo "Phase 3: PRODUCTION - Application Services"
    echo "============================================================================"
    echo "Connection: Tailscale network ONLY"
    echo "User: ${SSH_USER}"
    echo "Purpose: DNS, ingress, deploy user, advanced monitoring, encryption"
    echo "============================================================================"
    echo ""
    echo "Verifying Tailscale connectivity..."
    ;;
  *)
    echo "ERROR: Invalid phase '${PHASE}'. Must be: bootstrap, foundation, or production"
    echo ""
    echo "Usage:"
    echo "  ./scripts/run-ansible.sh <env> <host> <phase>"
    echo ""
    echo "Phases:"
    echo "  bootstrap   - Phase 1: Initial access setup (local IP, armand user)"
    echo "  foundation  - Phase 2: Network + security (local IP, ansible user)"
    echo "  production  - Phase 3: Application services (Tailscale ONLY, ansible user)"
    exit 1
    ;;
esac

echo "Using inventory: ${INVENTORY_FILE}"
echo "Running playbook: playbooks/${PLAYBOOK}.yml"
echo ""

# Mount SSH keys for authentication
SSH_KEY_MOUNT=""
SSH_KEY_NAME=""
if [[ "${PHASE}" == "bootstrap" ]]; then
  # Bootstrap: use armand's personal key (for connecting as armand user)
  if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_MOUNT="-v ${HOME}/.ssh/id_ed25519:/root/.ssh/id_ed25519:ro"
    SSH_KEY_NAME="id_ed25519"
  elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_MOUNT="-v ${HOME}/.ssh/id_rsa:/root/.ssh/id_rsa:ro"
    SSH_KEY_NAME="id_rsa"
  fi
else
  # Foundation and Production: use intergalactic_ansible key (for connecting as ansible user)
  if [[ -f "${HOME}/.ssh/intergalactic_ansible" ]]; then
    SSH_KEY_MOUNT="-v ${HOME}/.ssh/intergalactic_ansible:/root/.ssh/intergalactic_ansible:ro"
    SSH_KEY_NAME="intergalactic_ansible"
  elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_MOUNT="-v ${HOME}/.ssh/id_ed25519:/root/.ssh/id_ed25519:ro"
    SSH_KEY_NAME="id_ed25519"
  elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_MOUNT="-v ${HOME}/.ssh/id_rsa:/root/.ssh/id_rsa:ro"
    SSH_KEY_NAME="id_rsa"
  fi
fi

# SSH agent forwarding if available
SSH_AUTH_SOCK_MOUNT=""
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  SSH_AUTH_SOCK_MOUNT="-v ${SSH_AUTH_SOCK}:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
fi

# Configure SSH to use the correct key
if [[ -n "${SSH_KEY_NAME:-}" ]]; then
  export ANSIBLE_SSH_ARGS="-o IdentitiesOnly=yes -i /root/.ssh/${SSH_KEY_NAME}"
fi

# Run the playbook
docker run --rm -i \
  -v "${ROOT_DIR}:/repo" \
  ${SSH_KEY_MOUNT} \
  ${SSH_AUTH_SOCK_MOUNT} \
  -e ANSIBLE_SSH_ARGS="${ANSIBLE_SSH_ARGS:-}" \
  "${IMAGE}" \
  ansible-playbook -i "${INVENTORY_FILE}" "playbooks/${PLAYBOOK}.yml"

EXIT_CODE=$?

# Phase-specific post-execution messages
if [[ "${PHASE}" == "bootstrap" ]]; then
  if [[ ${EXIT_CODE} -ne 0 ]]; then
    echo ""
    echo "============================================================================"
    echo "ERROR: Bootstrap playbook failed with exit code ${EXIT_CODE}"
    echo "============================================================================"
    echo "The automation user may not have been created."
    echo "Please review the error messages above and fix any issues."
    echo "============================================================================"
    exit ${EXIT_CODE}
  else
    echo ""
    echo "============================================================================"
    echo "✓ Bootstrap completed successfully!"
    echo "============================================================================"
    echo "Next step: Run foundation phase"
    echo "  ./scripts/run-ansible.sh ${ENV_NAME} ${HOST} foundation"
    echo "============================================================================"
  fi
elif [[ "${PHASE}" == "foundation" ]]; then
  if [[ ${EXIT_CODE} -eq 0 ]]; then
    echo ""
    echo "============================================================================"
    echo "✓ Foundation completed successfully!"
    echo "============================================================================"
    echo "Next steps:"
    echo "  1. Get Tailscale hostname from output above, or run:"
    echo "     tailscale status | grep ${HOST}"
    echo ""
    echo "  2. Update hosts.yml with Tailscale hostname:"
    echo "     ${HOST}:"
    echo "       ansible_host: ${HOST}.tailnet-name.ts.net  # Or just '${HOST}' with MagicDNS"
    echo "       ansible_user: ansible"
    echo ""
    echo "  3. Run production phase:"
    echo "     ./scripts/run-ansible.sh ${ENV_NAME} ${HOST} production"
    echo "============================================================================"
  fi
elif [[ "${PHASE}" == "production" ]]; then
  if [[ ${EXIT_CODE} -eq 0 ]]; then
    echo ""
    echo "============================================================================"
    echo "✓ Production phase completed successfully!"
    echo "============================================================================"
    echo "All services are now deployed and running."
    echo "============================================================================"
  fi
fi

exit ${EXIT_CODE}
