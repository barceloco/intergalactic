#!/usr/bin/env bash
# Check arcturus's memory profiles (16gb, 48gb) against its real host_vars:
# active VMs, memory fit, shares. Runs in the ansible-runner container with a
# local connection; touches no host.
#
# Usage: ./scripts/test-arcturus-profiles.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="intergalactic-ansible-runner:latest"

if ! docker image inspect "${RUNNER}" > /dev/null 2>&1; then
  docker build -q -t "${RUNNER}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null
fi

for profile in 16gb 48gb; do
  echo "=== profile ${profile} ==="
  docker run --rm -v "${ROOT_DIR}:/repo:ro" -w /repo/ansible \
    -e ANSIBLE_STDOUT_CALLBACK=default -e ANSIBLE_DISPLAY_SKIPPED_HOSTS=false \
    --entrypoint ansible-playbook "${RUNNER}" \
    -i inventories/prod/hosts-production.yml -l arcturus \
    ../tests/arcturus/check-memory-profiles.yml \
    -e "arcturus_memory_profile=${profile}" \
    | grep -E '"(Profile|VMs|Read-only)|failed=|FAILED|fatal' || true
done
