#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:-prod}"
PLAY="${2:-rigel}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="intergalactic-ansible-runner:latest"

docker build -t "${IMAGE}" "${ROOT_DIR}/docker/ansible-runner"

# Mount SSH keys for authentication
# Bootstrap playbooks: use armand's personal key (id_ed25519) since we connect as armand user
# Regular playbooks: use intergalactic_ansible key since we connect as ansible user
SSH_KEY_MOUNT=""
SSH_KEY_NAME=""
if [[ "${PLAY}" == *"-bootstrap"* ]]; then
  # Bootstrap: use armand's personal key (for connecting as armand user)
  if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_MOUNT="-v ${HOME}/.ssh/id_ed25519:/root/.ssh/id_ed25519:ro"
    SSH_KEY_NAME="id_ed25519"
  elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_MOUNT="-v ${HOME}/.ssh/id_rsa:/root/.ssh/id_rsa:ro"
    SSH_KEY_NAME="id_rsa"
  fi
else
  # Production: use intergalactic_ansible key (for connecting as ansible user)
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

# Configure SSH to use the correct key
# For bootstrap: use id_ed25519 (armand's key)
# For production: use intergalactic_ansible (project key)
SSH_ARGS_ENV=""
if [[ -n "${SSH_KEY_NAME:-}" ]]; then
  SSH_ARGS_ENV="-e ANSIBLE_SSH_ARGS='-o IdentitiesOnly=yes -i /root/.ssh/${SSH_KEY_NAME}'"
fi

# Run the playbook and capture exit code
# The script mounts the appropriate key and tells Ansible to use it via SSH_ARGS
docker run --rm -i \
  -v "${ROOT_DIR}:/repo" \
  ${SSH_KEY_MOUNT} \
  ${SSH_AUTH_SOCK_MOUNT} \
  ${SSH_ARGS_ENV} \
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
