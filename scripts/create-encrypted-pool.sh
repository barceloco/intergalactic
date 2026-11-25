#!/usr/bin/env bash
# Create arcturus's encrypted ZFS pool, once, from the Mac. Run by the
# operator, never by automation: it asks for the passphrase, which exists only
# in your head or password manager afterwards. It never wipes a disk: disks
# must be empty, or the script stops and shows what is on them.
#
# Usage:
#   ./scripts/create-encrypted-pool.sh                        # list candidate disks
#   ./scripts/create-encrypted-pool.sh <disk-id> [<disk-id>]  # create the pool
#
# Disk ids are names under /dev/disk/by-id/ (e.g. nvme-WD_BLACK_SN850X_4000GB_XXXX),
# stable across reboots, unlike /dev/nvme0n1. Two disks make a STRIPE: one
# pool with both disks' capacity and no redundancy (the decided design; the
# Synology backup is the recovery path).
#
# Environment: ARCTURUS_HOST, ARCTURUS_SSH_KEY (as for unlock-arcturus.sh),
#              POOL (default tank).
set -euo pipefail

HOST="${ARCTURUS_HOST:-arcturus.tailb821ac.ts.net}"
KEY="${ARCTURUS_SSH_KEY:-${HOME}/.ssh/intergalactic_ansible}"
POOL="${POOL:-tank}"
SSH=(ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -i "${KEY}" "ansible@${HOST}")

if [ "$#" -eq 0 ]; then
  echo "Disks on ${HOST} (by-id names, size, model, mount points):"
  "${SSH[@]}" 'for d in /dev/disk/by-id/nvme-* /dev/disk/by-id/ata-*; do
      case "$d" in *-part*|*_1|*eui.*|*nvme-nvme.*) continue;; esac
      [ -e "$d" ] || continue
      dev=$(readlink -f "$d")
      printf "%s\n    %s\n" "$(basename "$d")" "$(lsblk -dno SIZE,MODEL "$dev") $(lsblk -no MOUNTPOINTS "$dev" | tr "\n" " ")"
    done'
  echo
  echo "The disk holding / (the system SSD) must NOT be used. Then run:"
  echo "  $0 <disk-id> [<disk-id>]"
  exit 0
fi

if "${SSH[@]}" "zpool list -H -o name ${POOL}" > /dev/null 2>&1; then
  echo "Pool ${POOL} already exists on ${HOST}. Nothing to do." >&2
  exit 1
fi

DEVS=()
for id in "$@"; do
  [[ "${id}" =~ ^[A-Za-z0-9._:-]+$ ]] || { echo "Invalid disk id: ${id}" >&2; exit 1; }
  dev="/dev/disk/by-id/${id}"
  # Refuse anything mounted, partitioned, or carrying a filesystem or RAID signature.
  report="$("${SSH[@]}" "set -e
    [ -b ${dev} ] || { echo MISSING; exit 0; }
    real=\$(readlink -f ${dev})
    if findmnt -rno SOURCE | grep -q \"^\${real}\"; then echo MOUNTED; exit 0; fi
    if [ \$(lsblk -no NAME \${real} | wc -l) -gt 1 ]; then echo PARTITIONED; exit 0; fi
    if [ -n \"\$(sudo -n wipefs -n \${real})\" ]; then echo SIGNATURES; exit 0; fi
    echo EMPTY")"
  case "${report}" in
    EMPTY) DEVS+=("${dev}") ;;
    MISSING) echo "No disk ${dev} on ${HOST}." >&2; exit 1 ;;
    *)
      echo "Refusing ${id}: ${report}." >&2
      echo "This disk is not empty. If (and only if) its contents are backed up or" >&2
      echo "unwanted, erase it yourself on ${HOST}, e.g.:" >&2
      echo "  sudo wipefs -a /dev/disk/by-id/${id}   # check the id twice" >&2
      exit 1 ;;
  esac
done

echo "About to create pool '${POOL}' on ${HOST}, a STRIPE (no redundancy) over:"
printf '  %s\n' "${DEVS[@]}"
read -r -p "Type the pool name to confirm: " confirm
[ "${confirm}" = "${POOL}" ] || { echo "Not confirmed." >&2; exit 1; }

IFS= read -r -s -p "New passphrase (20+ characters; keep it in your password manager): " p1; echo
IFS= read -r -s -p "Repeat the passphrase: " p2; echo
[ "${p1}" = "${p2}" ] || { echo "The passphrases differ." >&2; exit 1; }
[ "${#p1}" -ge 20 ] || { echo "Use at least 20 characters." >&2; exit 1; }
unset p2

# keylocation=prompt: the key is never stored; it must be supplied at each unlock.
printf '%s' "${p1}" | "${SSH[@]}" sudo -n zpool create \
  -o ashift=12 -o autotrim=on \
  -O encryption=aes-256-gcm -O keyformat=passphrase -O keylocation=prompt \
  -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl -O dnodesize=auto \
  -O mountpoint=/"${POOL}" "${POOL}" "${DEVS[@]}"
unset p1

"${SSH[@]}" "zpool status ${POOL}; zfs get -H encryption,keyformat,keylocation,keystatus ${POOL}"
echo
echo "Pool created and unlocked. Next: ./scripts/run-ansible.sh prod arcturus production"
