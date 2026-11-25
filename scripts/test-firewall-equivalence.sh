#!/usr/bin/env bash
# Prove a firewall change is neutral for the running hosts: render each host's
# nftables ruleset from a baseline ref and from the working tree (both with
# scripts/render-firewall.sh, both nft -c checked) and require byte-identical
# output. Touches no host.
#
# Usage: ./scripts/test-firewall-equivalence.sh [ref] [host...]
#   ref   baseline (default 304900d, the last commit before firewall_forward_mode)
#   host  hosts to compare (default: vega rigel)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${1:-304900d}"
shift || true
HOSTS=("$@")
[ "${#HOSTS[@]}" -gt 0 ] || HOSTS=(vega rigel)

WORK="$(mktemp -d)"
cleanup() {
  git -C "${ROOT_DIR}" worktree remove --force "${WORK}/baseline" > /dev/null 2>&1 || true
  rm -rf "${WORK}"
}
trap cleanup EXIT

git -C "${ROOT_DIR}" worktree add --detach "${WORK}/baseline" "${REF}" > /dev/null 2>&1

fail=0
for h in "${HOSTS[@]}"; do
  "${WORK}/baseline/scripts/render-firewall.sh" "${h}" > "${WORK}/${h}.baseline.nft" 2> /dev/null \
    || { echo "FAIL  ${h}: cannot render at ${REF}"; fail=1; continue; }
  "${ROOT_DIR}/scripts/render-firewall.sh" "${h}" > "${WORK}/${h}.current.nft" 2> /dev/null \
    || { echo "FAIL  ${h}: cannot render the working tree"; fail=1; continue; }
  if cmp -s "${WORK}/${h}.baseline.nft" "${WORK}/${h}.current.nft"; then
    echo "PASS  ${h}: firewall identical to ${REF} ($(wc -l < "${WORK}/${h}.current.nft" | tr -d ' ') lines)"
  else
    echo "FAIL  ${h}: firewall differs from ${REF}"
    diff "${WORK}/${h}.baseline.nft" "${WORK}/${h}.current.nft" || true
    fail=1
  fi
done
exit "${fail}"
