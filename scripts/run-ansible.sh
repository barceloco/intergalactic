#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:-prod}"
PLAY="${2:-rigel}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="intergalactic-ansible-runner:latest"

docker build -t "${IMAGE}" "${ROOT_DIR}/docker/ansible-runner"

# Mount SSH keys for authentication
SSH_KEY_MOUNT=""
if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
  SSH_KEY_MOUNT="-v ${HOME}/.ssh/id_ed25519:/root/.ssh/id_ed25519:ro"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
  SSH_KEY_MOUNT="-v ${HOME}/.ssh/id_rsa:/root/.ssh/id_rsa:ro"
fi

# Also try SSH agent forwarding if available
SSH_AUTH_SOCK_MOUNT=""
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  SSH_AUTH_SOCK_MOUNT="-v ${SSH_AUTH_SOCK}:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
fi

# Note: We don't mount known_hosts as a file because it causes file locking issues
# The playbooks will manage known_hosts inside the container using the known_hosts module
# Host keys are fetched and added securely on each run

# Determine which inventory to use
INVENTORY_FILE="inventories/${ENV_NAME}/hosts.yml"
if [[ "${PLAY}" == *"-bootstrap"* ]]; then
  INVENTORY_FILE="inventories/${ENV_NAME}/hosts-bootstrap.yml"
  echo "Using bootstrap inventory: ${INVENTORY_FILE}"
else
  echo "Using production inventory: ${INVENTORY_FILE}"
fi

# Run the playbook and capture exit code
docker run --rm -i \
  -v "${ROOT_DIR}:/repo" \
  ${SSH_KEY_MOUNT} \
  ${SSH_AUTH_SOCK_MOUNT} \
  "${IMAGE}" \
  ansible-playbook -i "${INVENTORY_FILE}" "playbooks/${PLAY}.yml"
EXIT_CODE=$?

# For bootstrap playbooks, check if user creation was successful
if [[ "${PLAY}" == *"-bootstrap"* ]]; then
  if [[ ${EXIT_CODE} -ne 0 ]]; then
    echo ""
    echo "============================================================================"
    echo "ERROR: Bootstrap playbook failed with exit code ${EXIT_CODE}"
    echo "============================================================================"
    echo "The automation user may not have been created."
    echo "Please review the error messages above and fix any issues."
    echo "============================================================================"
    exit ${EXIT_CODE}
  fi
fi

exit ${EXIT_CODE}
