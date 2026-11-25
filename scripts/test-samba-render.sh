#!/usr/bin/env bash
# Check that the samba role's smb.conf renders byte-identically to main's for
# the hosts that run it today (vega, rigel) with the role's default shares,
# and show phecda-style shares rendering. Uses Ansible's own template engine
# in the ansible-runner container; touches no host.
#
# Usage: ./scripts/test-samba-render.sh [ref]   (default ref: main)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${1:-main}"
RUNNER="intergalactic-ansible-runner:latest"

if ! docker image inspect "${RUNNER}" > /dev/null 2>&1; then
  docker build -q -t "${RUNNER}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null
fi

docker run --rm -v "${ROOT_DIR}:/repo:ro" -w /repo/ansible --entrypoint bash "${RUNNER}" -c '
  set -euo pipefail
  ref="$1"; out=$(mktemp -d)
  git -c safe.directory=/repo -C /repo show "${ref}:ansible/roles/samba/templates/smb.conf.j2" > "${out}/main.j2"
  render() { # <template> <dest> <host> [extra -e]
    ANSIBLE_LOCALHOST_WARNING=False ansible localhost -c local -i localhost, -m template \
      -a "src=$1 dest=$2" -e "hostname=$3" -e @roles/samba/defaults/main.yml "${@:4}" > /dev/null
  }
  fail=0
  for h in vega rigel; do
    render "${out}/main.j2" "${out}/main-${h}.conf" "${h}"
    render roles/samba/templates/smb.conf.j2 "${out}/branch-${h}.conf" "${h}"
    if cmp -s "${out}/main-${h}.conf" "${out}/branch-${h}.conf"; then
      echo "PASS  ${h}: smb.conf identical to ${ref}"
    else
      echo "FAIL  ${h}: smb.conf differs from ${ref}"; diff "${out}/main-${h}.conf" "${out}/branch-${h}.conf" || true; fail=1
    fi
  done
  cat > "${out}/phecda.yml" <<EOF
samba_shares:
  - {name: documents, comment: Documents, path: /mnt/documents}
  - {name: immich, comment: Photos (read-only), path: /mnt/immich, read_only: true}
EOF
  render roles/samba/templates/smb.conf.j2 "${out}/phecda.conf" phecda -e @"${out}/phecda.yml"
  if grep -q "^\[immich\]" "${out}/phecda.conf" && grep -A6 "^\[immich\]" "${out}/phecda.conf" | grep -q "read only = yes"; then
    echo "PASS  phecda-style shares render (read-only share marked read only)"
  else
    echo "FAIL  phecda-style shares"; cat "${out}/phecda.conf"; fail=1
  fi
  exit "${fail}"
' _ "${REF}"
