#!/usr/bin/env bash
# Unlock arcturus's encrypted pool from the Mac, then start its VMs in order.
#
# The passphrase is typed here (or piped in, e.g. from a password manager's
# command-line tool) and sent through SSH to the host's unlock helper, which
# hands it straight to `zfs load-key`. It is never stored on the host, on
# disk here, or in any log.
#
# Usage:
#   ./scripts/unlock-arcturus.sh                 # prompts for the passphrase
#   ./scripts/unlock-arcturus.sh --no-start      # unlock only, leave VMs off
#   <password-manager-cli> | ./scripts/unlock-arcturus.sh
#
# Environment: ARCTURUS_HOST (default arcturus.tailb821ac.ts.net),
#              ARCTURUS_SSH_KEY (default ~/.ssh/intergalactic_ansible).
set -euo pipefail

HOST="${ARCTURUS_HOST:-arcturus.tailb821ac.ts.net}"
KEY="${ARCTURUS_SSH_KEY:-${HOME}/.ssh/intergalactic_ansible}"
MODE="${1:-}"
case "${MODE}" in ""|--no-start) ;; *) echo "usage: $0 [--no-start]" >&2; exit 2 ;; esac

# Strict host key checking: a host we do not recognise never gets the passphrase.
SSH=(ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -i "${KEY}" "ansible@${HOST}")

status="$("${SSH[@]}" sudo -n /usr/local/sbin/proxmox-unlock --status)"
if [ "${status}" = available ]; then
  echo "Pool already unlocked; starting any VMs still off."
  printf '' | "${SSH[@]}" sudo -n /usr/local/sbin/proxmox-unlock ${MODE}
  exit 0
fi

if [ -t 0 ]; then
  read -r -s -p "Pool passphrase for ${HOST}: " pass; echo
else
  IFS= read -r pass
fi
[ -n "${pass}" ] || { echo "Empty passphrase." >&2; exit 1; }

printf '%s' "${pass}" | "${SSH[@]}" sudo -n /usr/local/sbin/proxmox-unlock ${MODE}
unset pass
