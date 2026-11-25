#!/usr/bin/env bash
# Check that os-upgrade.yml's workload snippets behave exactly as before on
# Docker-only hosts (vega, rigel) and list Proxmox VMs correctly on arcturus.
# Runs in the ansible-runner container with fake docker/qm commands; touches
# no host.
#
# Usage: ./scripts/test-os-upgrade-workloads.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="intergalactic-ansible-runner:latest"

if ! docker image inspect "${RUNNER}" > /dev/null 2>&1; then
  docker build -q -t "${RUNNER}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null
fi

docker run --rm -v "${ROOT_DIR}:/repo:ro" -w /repo --entrypoint python3 \
  "${RUNNER}" tests/unit/check_os_upgrade_workloads.py
