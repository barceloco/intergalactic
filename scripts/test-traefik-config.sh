#!/usr/bin/env bash
# Start the pinned Traefik image locally on the configuration rigel would get
# (real inventory, role edge_ingress) and check that Traefik accepts both
# files and serves every route. Run it before changing the image or the
# templates: an unknown field makes Traefik reject the whole route file.
#
# Offline on purpose (--network none): no ACME account is registered and no
# backend is contacted. Each route must answer through its middleware with the
# test fingerprint; backends are unreachable, so 502/503 is expected.
#
# Usage: ./scripts/test-traefik-config.sh [host]   (default: rigel)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${1:-rigel}"
RUNNER="intergalactic-ansible-runner:latest"
TEST_ID="0123456789ab"
OUT="$(mktemp -d)"
NAME="traefik-config-test-$$"
trap 'docker rm -f "${NAME}" > /dev/null 2>&1 || true; rm -rf "${OUT}"' EXIT
mkdir -p "${OUT}/dynamic"

if ! docker image inspect "${RUNNER}" > /dev/null 2>&1; then
  docker build -q -t "${RUNNER}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null
fi

ansible_cmd() {  # ansible_cmd <module> <args>
  printf '%s' "ANSIBLE_LOCALHOST_WARNING=False ansible ${HOST} -i inventories/prod/hosts-production.yml \
    -c local -m $1 -e @roles/edge_ingress/defaults/main.yml \
    -e @inventories/prod/host_vars/${HOST}.yml -e edge_ingress_config_id=${TEST_ID} -a '$2'"
}

docker run --rm -v "${ROOT_DIR}:/repo:ro" -v "${OUT}:/out" -w /repo/ansible \
  --entrypoint bash "${RUNNER}" -c "
  set -euo pipefail
  $(ansible_cmd template 'src=roles/edge_ingress/templates/traefik.yml.j2 dest=/out/traefik.yml mode=0644') > /dev/null
  $(ansible_cmd template 'src=roles/edge_ingress/templates/dynamic.yml.j2 dest=/out/dynamic/dynamic.yml mode=0644') > /dev/null
  $(ansible_cmd debug 'msg={{ edge_ingress_image }}:{{ edge_ingress_image_tag }}@{{ edge_ingress_image_digest }}') \
    | sed -n 's/.*\"msg\": \"\(.*\)\".*/\1/p' > /out/image
  $(ansible_cmd debug 'msg={{ edge_ingress_data_dir }}') | sed -n 's/.*\"msg\": \"\(.*\)\".*/\1/p' > /out/datadir
  $(ansible_cmd debug 'msg={{ edge_ingress_routes | map(attribute=\"host\") | join(\" \") }}') \
    | sed -n 's/.*\"msg\": \"\(.*\)\".*/\1/p' > /out/hosts
  $(ansible_cmd template 'src=/repo/scripts/lib/traefik-extra-routers.j2 dest=/out/extra mode=0644') > /dev/null"
IMAGE="$(cat "${OUT}/image")"; DATADIR="$(cat "${OUT}/datadir")"; HOSTS="$(cat "${OUT}/hosts")"
if [ -z "${IMAGE}" ] || [ -z "${DATADIR}" ] || [ -z "${HOSTS}" ]; then
  echo "FAIL  could not render the configuration"; exit 1
fi
echo "image: ${IMAGE}"
: > "${OUT}/acme.json"; chmod 600 "${OUT}/acme.json"
chmod -R a+rX "${OUT}/dynamic" "${OUT}/traefik.yml"

docker run -d --name "${NAME}" --network none \
  -v "${OUT}/traefik.yml:/traefik.yml:ro" -v "${OUT}/dynamic:/dynamic:ro" \
  -v "${OUT}/acme.json:${DATADIR}/acme.json" \
  "${IMAGE}" --configFile=/traefik.yml > /dev/null

fail=0
sleep 8
if [ "$(docker inspect -f '{{.State.Running}}' "${NAME}")" != true ]; then
  echo "FAIL  Traefik exited:"; docker logs "${NAME}" 2>&1 | tail -20; exit 1
fi
echo "PASS  Traefik started on the static configuration"

if docker logs "${NAME}" 2>&1 | grep -i -E 'field not found|cannot (decode|unmarshal)|watcher callback|building configuration|unknown field'; then
  echo "FAIL  Traefik rejected part of the configuration (see above)"; fail=1
else
  echo "PASS  no configuration errors in the log"
fi

# Offline, every backend is unreachable: a loaded route answers 502/503/504
# from its service; a missing route gets Traefik's own 404. (The fingerprint
# header is checked on the real host by the gate; busybox wget prints no
# headers for an error status.)
for host in ${HOSTS}; do
  status="$(docker exec "${NAME}" wget -S -O /dev/null --no-check-certificate \
    --header "Host: ${host}" https://127.0.0.1/ 2>&1 | sed -n 's/^ *HTTP\/[0-9.]* \([0-9]*\).*/\1/p' | head -1 || true)"
  case "${status}" in
    502|503|504) echo "PASS  route ${host} (HTTP ${status} from its service)" ;;
    *) echo "FAIL  route ${host}: HTTP '${status}' (404 = route not loaded)"; fail=1 ;;
  esac
done

# Extra routers (edge_ingress_extra_routers), each on its entry point's port.
while read -r name host port path; do
  [ -n "${name}" ] || continue
  status="$(docker exec "${NAME}" wget -S -O /dev/null --no-check-certificate \
    --header "Host: ${host}" "https://127.0.0.1:${port}${path}" 2>&1 | sed -n 's/^ *HTTP\/[0-9.]* \([0-9]*\).*/\1/p' | head -1 || true)"
  case "${status}" in
    502|503|504) echo "PASS  extra router ${name} on :${port} (HTTP ${status} from its service)" ;;
    *) echo "FAIL  extra router ${name} on :${port}: HTTP '${status}' (404 = router not loaded)"; fail=1 ;;
  esac
done < "${OUT}/extra"
if [ "${fail}" -ne 0 ]; then
  first="${HOSTS%% *}"
  echo "--- response for ${first}:"
  docker exec "${NAME}" wget -S -O /dev/null --no-check-certificate --header "Host: ${first}" https://127.0.0.1/ 2>&1 | head -15 || true
  echo "--- Traefik log (last 15 lines):"
  docker logs "${NAME}" 2>&1 | tail -15
fi
exit "${fail}"
