#!/usr/bin/env bash
# Download Debian 13's "generic" disk image (amd64, raw) and verify it against
# the SHA512SUMS Debian publishes next to it. Runs in a container; writes only
# to build/ (gitignored). It never writes to a disk: it prints the commands,
# because choosing the target disk is a destructive decision for a human.
#
# Usage: ./scripts/fetch-debian-image.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="https://cloud.debian.org/images/cloud/trixie/latest"
IMAGE="debian-13-generic-amd64.raw"
OUT_DIR="${ROOT_DIR}/build/images"
mkdir -p "${OUT_DIR}"

docker run --rm -v "${OUT_DIR}:/out" -w /out debian:trixie-slim sh -c "
  set -eu
  export DEBIAN_FRONTEND=noninteractive
  apt-get -qq update >/dev/null && apt-get -qq install -y curl ca-certificates >/dev/null
  curl -fsSL -o SHA512SUMS '${BASE}/SHA512SUMS'
  if [ -f '${IMAGE}' ] && grep -E ' ${IMAGE}\$' SHA512SUMS | sha512sum -c --status; then
    echo 'Image already present and verified.'
  else
    curl -fL --progress-bar -o '${IMAGE}' '${BASE}/${IMAGE}'
    grep -E ' ${IMAGE}\$' SHA512SUMS | sha512sum -c
  fi
"

cat <<EOF

Verified image: ${OUT_DIR}/${IMAGE}

Write it to the NVMe (in a USB enclosure). This ERASES the target disk, so
check the size and name in 'diskutil list' before running dd:
  diskutil list                                   # find the NVMe, e.g. /dev/disk7
  diskutil unmountDisk /dev/diskN
  sudo dd if="${OUT_DIR}/${IMAGE}" of=/dev/rdiskN bs=4m status=progress
  diskutil eject /dev/diskN

At first boot the image grows its root partition to fill the NVMe.
EOF
