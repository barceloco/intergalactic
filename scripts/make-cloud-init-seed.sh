#!/usr/bin/env bash
# Render the first-boot cloud-init seed (user-data + meta-data) for a bare-metal
# host installed from Debian's "generic" image. Runs in the ansible runner
# container; touches no host. Output: build/seed-<host>/ (gitignored).
#
# Usage: ./scripts/make-cloud-init-seed.sh <host>
set -euo pipefail

HOST="${1:?usage: $0 <host>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="intergalactic-ansible-runner:latest"
OUT_DIR="${ROOT_DIR}/build/seed-${HOST}"

if ! docker image inspect "${RUNNER}" > /dev/null 2>&1; then
  docker build -q -t "${RUNNER}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null
fi

mkdir -p "${OUT_DIR}"
LOG="$(mktemp)"
trap 'rm -f "${LOG}"' EXIT
docker run --rm \
  -v "${ROOT_DIR}:/repo:ro" \
  -v "${OUT_DIR}:/out" \
  "${RUNNER}" \
  ansible-playbook -i inventories/prod/hosts-bootstrap.yml playbooks/make-cloud-init-seed.yml \
    -e "seed_host=${HOST}" -e seed_out_dir=/out > "${LOG}" 2>&1 \
  || { cat "${LOG}"; exit 1; }

cat <<EOF
Seed written to ${OUT_DIR}/ (user-data, meta-data; public keys only).

Put it on a USB stick (this ERASES the stick):
  diskutil list                                   # find the stick, e.g. /dev/disk6
  diskutil eraseDisk FAT32 CIDATA MBRFormat /dev/diskN
  cp "${OUT_DIR}/user-data" "${OUT_DIR}/meta-data" /Volumes/CIDATA/
  diskutil eject /dev/diskN

The volume name must be exactly CIDATA: cloud-init finds the seed by that label.
EOF
