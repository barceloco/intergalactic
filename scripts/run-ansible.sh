#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:-prod}"
PLAY="${2:-rigel}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="intergalactic-ansible-runner:latest"

docker build -t "${IMAGE}" "${ROOT_DIR}/docker/ansible-runner"

SSH_AUTH_SOCK_MOUNT=""
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  SSH_AUTH_SOCK_MOUNT="-v ${SSH_AUTH_SOCK}:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
fi

docker run --rm -it \
  -v "${ROOT_DIR}:/repo" \
  ${SSH_AUTH_SOCK_MOUNT} \
  "${IMAGE}" \
  ansible-playbook -i "inventories/${ENV_NAME}/hosts.yml" "playbooks/${PLAY}.yml"
