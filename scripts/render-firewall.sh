#!/usr/bin/env bash
# Render a host's nftables ruleset from the inventory (no connection to the
# host), validate it like the firewall_nftables role does, and syntax-check it
# with nft on Debian trixie. Prints the ruleset for review.
#
# Usage: ./scripts/render-firewall.sh <host>
set -euo pipefail

HOST="${1:?usage: $0 <host>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="intergalactic-ansible-runner:latest"
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "${OUT_DIR}"' EXIT

if ! docker image inspect "${RUNNER}" > /dev/null 2>&1; then
  docker build -q -t "${RUNNER}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null
fi

docker run --rm \
  -v "${ROOT_DIR}:/repo:ro" \
  -v "${OUT_DIR}:/out" \
  "${RUNNER}" \
  ansible-playbook -i inventories/prod/hosts-production.yml playbooks/render-firewall.yml \
    -e "render_hosts=${HOST}" -e render_out_dir=/out > "${OUT_DIR}/ansible.log" 2>&1 \
  || { cat "${OUT_DIR}/ansible.log"; exit 1; }

RULES="${OUT_DIR}/${HOST}.nft"
[ -s "${RULES}" ] || { cat "${OUT_DIR}/ansible.log"; echo "ERROR: nothing rendered for ${HOST}"; exit 1; }

# nft -c needs the kernel's nf_tables, hence --privileged; it changes nothing
# (check mode, inside a throwaway container's own network namespace).
docker run --rm --privileged -v "${OUT_DIR}:/out:ro" debian:trixie-slim sh -c \
  'export DEBIAN_FRONTEND=noninteractive; apt-get -qq update > /dev/null && apt-get -qq install -y nftables > /dev/null && nft -c -f /out/'"${HOST}"'.nft' \
  || { echo "ERROR: nft syntax check failed for ${HOST}"; exit 1; }

cat "${RULES}"
echo "# OK: ${HOST} rules validated and pass 'nft -c' on Debian trixie" >&2
