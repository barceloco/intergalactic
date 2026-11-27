#!/usr/bin/env bash
# Run only the edge_ingress gate against a host: every route must answer
# through Traefik on that host with a valid certificate and the fingerprint of
# the routes on disk. Read-only; changes nothing.
#
# Usage: ./scripts/verify-edge-gate.sh <host>    (e.g. rigel)
set -euo pipefail

HOST="${1:?usage: verify-edge-gate.sh <host>}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec ./scripts/run-ansible.sh prod "${HOST}" production --tags edge_gate
