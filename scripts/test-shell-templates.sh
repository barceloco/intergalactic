#!/usr/bin/env bash
# Render every shell-script template of the arcturus roles with the role's
# defaults (Ansible's own template engine, in the ansible-runner container),
# then check each with `bash -n` and shellcheck (warnings and above) on Debian
# trixie. Shell files shipped as-is (roles/*/files/*) are checked too.
# Touches no host.
#
# Usage: ./scripts/test-shell-templates.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="intergalactic-ansible-runner:latest"
ROLES=(proxmox_storage backup_hub notify host_alerts)
OUT="$(mktemp -d)"
trap 'rm -rf "${OUT}"' EXIT

if ! docker image inspect "${RUNNER}" > /dev/null 2>&1; then
  docker build -q -t "${RUNNER}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null
fi

docker run --rm -v "${ROOT_DIR}:/repo:ro" -v "${OUT}:/out" -w /repo/ansible \
  --entrypoint bash "${RUNNER}" -c '
  set -euo pipefail
  for role in "$@"; do
    for t in roles/${role}/templates/*.sh.j2; do
      [ -e "${t}" ] || continue
      name="${role}__$(basename "${t}" .j2)"
      ANSIBLE_LOCALHOST_WARNING=False ansible localhost -c local -i localhost, -m template \
        -a "src=${t} dest=/out/${name}" -e @roles/${role}/defaults/main.yml \
        -e inventory_hostname=arcturus -e proxmox_vms=[] > /dev/null \
        || { echo "FAIL  render ${t}"; exit 1; }
    done
    for f in roles/${role}/files/*; do
      [ -f "${f}" ] || continue
      head -1 "${f}" | grep -q "^#!.*sh" && cp "${f}" "/out/${role}__$(basename "${f}")"
    done
  done' _ "${ROLES[@]}"

docker run --rm -v "${OUT}:/out:ro" debian:trixie-slim sh -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get -qq update > /dev/null && apt-get -qq install -y shellcheck > /dev/null
  fail=0
  for f in /out/*; do
    shell=$(head -1 "$f" | sed "s|^#!.*/||; s| .*||")
    case "$shell" in env) shell=$(head -1 "$f" | awk "{print \$2}") ;; esac
    if ! "$shell" -n "$f" 2> /tmp/err; then echo "FAIL  syntax $(basename "$f")"; cat /tmp/err; fail=1; continue; fi
    if shellcheck -S warning "$f" > /tmp/sc 2>&1; then
      echo "PASS  $(basename "$f")"
    else
      echo "FAIL  shellcheck $(basename "$f")"; cat /tmp/sc; fail=1
    fi
  done
  exit $fail'
