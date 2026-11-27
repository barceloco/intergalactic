#!/usr/bin/env bash
# Render Homepage's configuration exactly as vega would get it (real inventory,
# role app_homepage) and run the pinned Homepage image locally against it, with
# the same hardening as on the host (unprivileged user, read-only filesystem
# and configuration, no capabilities). Checks that Homepage accepts every
# file, serves the generated groups, that each app tile's status check and the
# Gatus widget work. Touches no host; the status checks reach the real routes
# over this machine's tailnet connection.
#
# Usage: ./scripts/test-homepage-config.sh [host]   (default: vega)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${1:-vega}"
RUNNER="intergalactic-ansible-runner:latest"
JQ="ghcr.io/jqlang/jq:1.7.1"
OUT="$(mktemp -d)"
NAME="homepage-config-test-$$"
trap 'docker rm -f "${NAME}" > /dev/null 2>&1 || true; rm -rf "${OUT}"' EXIT
mkdir -p "${OUT}/config"

if ! docker image inspect "${RUNNER}" > /dev/null 2>&1; then
  docker build -q -t "${RUNNER}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null
fi

render() {  # render <template> <dest under /out>
  printf %s "ANSIBLE_LOCALHOST_WARNING=False ansible ${HOST} -i inventories/prod/hosts-production.yml \
    -c local -m template -e @roles/app_homepage/defaults/main.yml \
    -e @inventories/prod/host_vars/${HOST}.yml \
    -a 'src=roles/app_homepage/templates/$1 dest=/out/$2 mode=0644' > /dev/null"
}
value() {  # value <jinja expression> <dest under /out>
  printf %s "ANSIBLE_LOCALHOST_WARNING=False ansible ${HOST} -i inventories/prod/hosts-production.yml \
    -c local -m debug -e @roles/app_homepage/defaults/main.yml \
    -e @inventories/prod/host_vars/${HOST}.yml -a 'msg=$1' \
    | sed -n 's/.*\"msg\": \"\(.*\)\".*/\1/p' > /out/$2"
}

docker run --rm -v "${ROOT_DIR}:/repo:ro" -v "${OUT}:/out" -w /repo/ansible \
  --entrypoint bash "${RUNNER}" -c "
  set -euo pipefail
  $(render settings.yaml.j2 config/settings.yaml)
  $(render services.yaml.j2 config/services.yaml)
  $(render empty-list.yaml.j2 config/widgets.yaml)
  $(render empty-list.yaml.j2 config/bookmarks.yaml)
  $(render empty.yaml.j2 config/docker.yaml)
  $(render empty.yaml.j2 config/kubernetes.yaml)
  $(render empty.yaml.j2 config/proxmox.yaml)
  $(value '{{ homepage_image }}:{{ homepage_image_tag }}@{{ homepage_image_digest }}' image)
  $(value '{{ homepage_dns_server }}' dns)
  $(value '{{ homepage_hostname }}' hostname)"
: > "${OUT}/config/custom.css"
: > "${OUT}/config/custom.js"
IMAGE="$(cat "${OUT}/image")"; DNS="$(cat "${OUT}/dns")"; HOSTNAME_="$(cat "${OUT}/hostname")"
if [ -z "${IMAGE}" ] || [ -z "${DNS}" ] || [ -z "${HOSTNAME_}" ]; then echo "FAIL  could not resolve the settings"; exit 1; fi
echo "image: ${IMAGE}"
chmod -R a+rX "${OUT}/config"

docker run -d --name "${NAME}" --user 1000:1000 --read-only --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs /tmp:size=16m,mode=1777 \
  --tmpfs /app/.next/cache:size=64m,uid=1000,gid=1000,mode=0700 \
  --dns "${DNS}" \
  -e HOMEPAGE_ALLOWED_HOSTS="${HOSTNAME_}" -e LOG_TARGETS=stdout -e NEXT_TELEMETRY_DISABLED=1 \
  -v "${OUT}/config:/app/config:ro" -p 127.0.0.1::3000 "${IMAGE}" > /dev/null
PORT="$(docker port "${NAME}" 3000/tcp | head -1 | sed 's/.*://')"
get() { curl -fsS --max-time 30 -H "Host: ${HOSTNAME_}" "http://127.0.0.1:${PORT}$1"; }

for _ in $(seq 1 60); do
  if get /api/healthcheck > /dev/null 2>&1; then break; fi
  if [ "$(docker inspect -f '{{.State.Running}}' "${NAME}")" != true ]; then
    echo "FAIL  Homepage exited:"; docker logs "${NAME}" 2>&1 | tail -20; exit 1
  fi
  sleep 1
done
get /api/healthcheck > /dev/null || { echo "FAIL  no /api/healthcheck"; docker logs "${NAME}" 2>&1 | tail; exit 1; }
echo "PASS  Homepage healthy as an unprivileged, read-only container"

fail=0
errors="$(get /api/validate)"
if [ "${errors}" = "[]" ]; then echo "PASS  every configuration file accepted"; else echo "FAIL  configuration errors: ${errors}"; fail=1; fi

services="$(get /api/services)"
groups="$(printf '%s' "${services}" | docker run --rm -i "${JQ}" -r '[.[].name] | join(",")')"
if [ "${groups}" = "Apps,Monitoring,Hosts" ]; then echo "PASS  groups: ${groups}"; else echo "FAIL  groups: ${groups}"; fail=1; fi

while IFS= read -r app; do
  status="$(get "/api/siteMonitor?groupName=Apps&serviceName=${app}" \
    | docker run --rm -i "${JQ}" -r '.status // "error"' 2>/dev/null || echo error)"
  if [[ "${status}" =~ ^[23][0-9][0-9]$ ]]; then echo "PASS  [Apps] ${app}: HTTP ${status}"
  else echo "FAIL  [Apps] ${app}: ${status}"; fail=1; fi
done < <(printf '%s' "${services}" | docker run --rm -i "${JQ}" -r '.[] | select(.name == "Apps") | .services[].name')

gatus="$(get "/api/services/proxy?group=Monitoring&service=Gatus&index=0&endpoint=status" \
  | docker run --rm -i "${JQ}" -r 'length' 2>/dev/null || echo error)"
if [[ "${gatus}" =~ ^[0-9]+$ ]] && [ "${gatus}" -gt 0 ]; then echo "PASS  [Monitoring] Gatus widget: ${gatus} endpoints"
else echo "FAIL  [Monitoring] Gatus widget: ${gatus}"; fail=1; fi

if docker logs "${NAME}" 2>&1 | grep -E -i 'EROFS|EACCES|permission denied|read-only file system'; then
  echo "FAIL  Homepage tried to write outside its writable paths (see above)"; fail=1
else
  echo "PASS  no write errors in the log"
fi
exit "${fail}"
