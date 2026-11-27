#!/usr/bin/env bash
# Render Gatus' configuration exactly as vega would get it (real inventory,
# role app_gatus) and run the pinned Gatus image locally against it. Gatus
# validates the configuration at start; then the script waits for the first
# round of checks and prints each endpoint's result. Alerts go nowhere (a
# dummy ntfy URL on 127.0.0.1). Touches no host; the checks themselves reach
# the real routes and DNS servers over this machine's tailnet connection.
#
# Usage: ./scripts/test-gatus-config.sh [host]   (default: vega)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${1:-vega}"
RUNNER="intergalactic-ansible-runner:latest"
OUT="$(mktemp -d)"
NAME="gatus-config-test-$$"
trap 'docker rm -f "${NAME}" > /dev/null 2>&1 || true; rm -rf "${OUT}"' EXIT

if ! docker image inspect "${RUNNER}" > /dev/null 2>&1; then
  docker build -q -t "${RUNNER}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null
fi

# Render (config.yaml holds no secret; gatus.env is not rendered).
docker run --rm -v "${ROOT_DIR}:/repo:ro" -v "${OUT}:/out" -w /repo/ansible \
  --entrypoint bash "${RUNNER}" -c "
  set -euo pipefail
  ANSIBLE_LOCALHOST_WARNING=False ansible ${HOST} -i inventories/prod/hosts-production.yml \
    -c local -m template -e @roles/app_gatus/defaults/main.yml \
    -e @inventories/prod/host_vars/${HOST}.yml \
    -a 'src=roles/app_gatus/templates/config.yaml.j2 dest=/out/config.yaml mode=0644' > /dev/null
  ANSIBLE_LOCALHOST_WARNING=False ansible ${HOST} -i inventories/prod/hosts-production.yml \
    -c local -m debug -e @roles/app_gatus/defaults/main.yml \
    -e @inventories/prod/host_vars/${HOST}.yml \
    -a 'msg={{ gatus_image }}:{{ gatus_image_tag }}@{{ gatus_image_digest }}' \
    | sed -n 's/.*\"msg\": \"\(.*\)\".*/\1/p' > /out/image"
IMAGE="$(cat "${OUT}/image")"
[ -n "${IMAGE}" ] || { echo "FAIL  could not resolve the image"; exit 1; }
echo "image: ${IMAGE}"
echo "endpoints: $(grep -c '^  - name:' "${OUT}/config.yaml")"

docker run -d --name "${NAME}" --user 65534:65534 --read-only --cap-drop ALL \
  --security-opt no-new-privileges:true \
  -e NTFY_URL=https://127.0.0.1:9 -e NTFY_TOPIC=config-test-not-a-topic -e NTFY_TOKEN= \
  -v "${OUT}/config.yaml:/config/config.yaml:ro" -p 127.0.0.1::8080 "${IMAGE}" > /dev/null
PORT="$(docker port "${NAME}" 8080/tcp | head -1 | sed 's/.*://')"

for _ in $(seq 1 30); do
  if curl -fs "http://127.0.0.1:${PORT}/health" > /dev/null 2>&1; then break; fi
  if [ "$(docker inspect -f '{{.State.Running}}' "${NAME}")" != true ]; then
    echo "FAIL  Gatus exited (invalid configuration?):"; docker logs "${NAME}" 2>&1 | tail -20; exit 1
  fi
  sleep 1
done
curl -fs "http://127.0.0.1:${PORT}/health" > /dev/null || { echo "FAIL  no /health"; docker logs "${NAME}" | tail; exit 1; }
echo "PASS  configuration accepted, Gatus healthy"

sleep 25
fail=0
while IFS=$'\t' read -r group name ok errors; do
  if [ "${ok}" = true ]; then echo "PASS  [${group}] ${name}"; else echo "FAIL  [${group}] ${name}: ${errors}"; fail=1; fi
done < <(curl -fs "http://127.0.0.1:${PORT}/api/v1/endpoints/statuses" \
  | docker run --rm -i ghcr.io/jqlang/jq:1.7.1 -r '.[] | [.group, .name, (.results[-1].success // false | tostring),
      ((.results[-1].conditionResults // []) | map(select(.success | not) | .condition) | join("; "))] | @tsv')
exit "${fail}"
