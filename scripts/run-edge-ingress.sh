#!/usr/bin/env bash
# Quick script to deploy/update edge_ingress (Traefik) role only
# Skips validation and other roles for faster iteration
# Usage: ./scripts/run-edge-ingress.sh [prod|dev] [rigel|vega|...]

set -euo pipefail

ENV_NAME="${1:-prod}"
HOST="${2:-rigel}"
shift 2  # Remove consumed arguments so "$@" only contains additional args

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="intergalactic-ansible-runner:latest"
DOCKERFILE="${ROOT_DIR}/docker/ansible-runner/Dockerfile"

# Use cached image if available
FORCE_REBUILD="${FORCE_REBUILD:-false}"
if [[ "${FORCE_REBUILD}" == "true" ]] || ! docker image inspect "${IMAGE}" &> /dev/null; then
  echo "Building Docker image..."
  docker build -t "${IMAGE}" "${ROOT_DIR}/docker/ansible-runner"
else
  echo "Using cached Docker image (use FORCE_REBUILD=true to rebuild)"
fi

INVENTORY_FILE="inventories/${ENV_NAME}/hosts-production.yml"
PLAYBOOK="${HOST}-production"
SSH_USER="ansible"

echo "============================================================================"
echo "Quick Edge Ingress (Traefik) Deployment"
echo "============================================================================"
echo "Host: ${HOST}"
echo "Environment: ${ENV_NAME}"
echo "Inventory: ${INVENTORY_FILE}"
echo "Skipping: validation, health-check tags"
echo "============================================================================"
echo ""

# Mount SSH keys for authentication
SSH_KEY_MOUNT=""
SSH_KEY_NAME=""
if [[ -f "${HOME}/.ssh/intergalactic_ansible" ]]; then
  SSH_KEY_NAME="intergalactic_ansible"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
  SSH_KEY_NAME="id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
  SSH_KEY_NAME="id_rsa"
else
  echo "ERROR: No SSH key found. Expected one of:"
  echo "  ~/.ssh/intergalactic_ansible"
  echo "  ~/.ssh/id_ed25519"
  echo "  ~/.ssh/id_rsa"
  exit 1
fi

SSH_KEY_PATH="${HOME}/.ssh/${SSH_KEY_NAME}"
SSH_KEY_MOUNT="-v ${SSH_KEY_PATH}:/root/.ssh/${SSH_KEY_NAME}:ro"

# Configure SSH to use the correct key
export ANSIBLE_SSH_ARGS="-o IdentitiesOnly=yes -i /root/.ssh/${SSH_KEY_NAME}"

# SSH agent forwarding if available
SSH_AUTH_SOCK_MOUNT=""
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  SSH_AUTH_SOCK_MOUNT="-v ${SSH_AUTH_SOCK}:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
fi

# Run Ansible in Docker container
docker run --rm -i \
  -v "${ROOT_DIR}:/repo" \
  -w /repo/ansible \
  ${SSH_KEY_MOUNT} \
  ${SSH_AUTH_SOCK_MOUNT} \
  -e ANSIBLE_HOST_KEY_CHECKING=False \
  -e ANSIBLE_SSH_ARGS="${ANSIBLE_SSH_ARGS:-}" \
  "${IMAGE}" \
  ansible-playbook \
    -i "${INVENTORY_FILE}" \
    "playbooks/${PLAYBOOK}.yml" \
    --tags "production,services" \
    --skip-tags "validation,health-check" \
    --limit "${HOST}" \
    "$@"

echo ""
echo "============================================================================"
echo "✓ Edge ingress deployment complete"
echo "============================================================================"
echo ""
echo "To run validation separately:"
echo "  ./scripts/run-ansible.sh ${ENV_NAME} ${HOST} production --tags validation,health-check"
