#!/usr/bin/env bash
# Start the pinned CoreDNS image locally on the Corefile rigel would get (real
# inventory, role internal_dns), mounted as a directory exactly as on the
# host. Checks that every internal name resolves, then adds a name to the
# Corefile and checks that it resolves WITHOUT a restart (reload plugin).
# Touches no host. Needs dig on this machine.
#
# Usage: ./scripts/test-coredns-image.sh [host]   (default: rigel)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${1:-rigel}"
RUNNER="intergalactic-ansible-runner:latest"
OUT="$(mktemp -d)"
NAME="coredns-image-test-$$"
trap 'docker rm -f "${NAME}" > /dev/null 2>&1 || true; rm -rf "${OUT}"' EXIT

if ! docker image inspect "${RUNNER}" > /dev/null 2>&1; then
  docker build -q -t "${RUNNER}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null
fi

# Host IPs are looked up live on the host; here every name gets the edge
# host's address (the template's fallback), which is enough to test serving.
cat > "${OUT}/test-vars.yml" <<EOF
internal_dns_host_ips: {}
tailscale_ip: "{{ fleet_tailscale_ipv4.${HOST} }}"
EOF
ansible_cmd() {  # ansible_cmd <module> <args>
  printf '%s' "ANSIBLE_LOCALHOST_WARNING=False ansible ${HOST} -i inventories/prod/hosts-production.yml \
    -c local -m $1 -e @roles/internal_dns/defaults/main.yml -e @inventories/prod/host_vars/${HOST}.yml \
    -e @/out/test-vars.yml -a '$2'"
}

docker run --rm -v "${ROOT_DIR}:/repo:ro" -v "${OUT}:/out" -w /repo/ansible \
  --entrypoint bash "${RUNNER}" -c "
  set -euo pipefail
  $(ansible_cmd template 'src=roles/internal_dns/templates/Corefile.j2 dest=/out/Corefile mode=0644') > /dev/null
  $(ansible_cmd debug 'msg={{ internal_dns_image }}:{{ internal_dns_image_tag }}@{{ internal_dns_image_digest }}') \
    | sed -n 's/.*\"msg\": \"\(.*\)\".*/\1/p' > /out/image
  $(ansible_cmd debug 'msg={{ internal_dns_domain }}') | sed -n 's/.*\"msg\": \"\(.*\)\".*/\1/p' > /out/domain
  $(ansible_cmd debug 'msg={{ internal_dns_private_hosts | join(\" \") }}') \
    | sed -n 's/.*\"msg\": \"\(.*\)\".*/\1/p' > /out/hosts"
IMAGE="$(cat "${OUT}/image")"; DOMAIN="$(cat "${OUT}/domain")"; HOSTS="$(cat "${OUT}/hosts")"
if [ -z "${IMAGE}" ] || [ -z "${DOMAIN}" ] || [ -z "${HOSTS}" ]; then
  echo "FAIL  could not render the Corefile"; exit 1
fi
rm -f "${OUT}/image" "${OUT}/domain" "${OUT}/hosts" "${OUT}/test-vars.yml"
chmod -R a+rX "${OUT}"
echo "image: ${IMAGE}"

docker run -d --name "${NAME}" -p 127.0.0.1::53/udp -v "${OUT}:/etc/coredns:ro" \
  "${IMAGE}" -conf /etc/coredns/Corefile > /dev/null
PORT="$(docker port "${NAME}" 53/udp | head -1 | sed 's/.*://')"
resolves() { dig @127.0.0.1 -p "${PORT}" +timeout=2 +tries=1 +noall +comments "$1" | grep -q 'status: NOERROR'; }

sleep 3
if [ "$(docker inspect -f '{{.State.Running}}' "${NAME}")" != true ]; then
  echo "FAIL  CoreDNS exited:"; docker logs "${NAME}" 2>&1 | tail -20; exit 1
fi
echo "PASS  CoreDNS started on the rendered Corefile"

fail=0
for h in ${HOSTS}; do
  if resolves "${h}.${DOMAIN}"; then echo "PASS  ${h}.${DOMAIN}"; else echo "FAIL  ${h}.${DOMAIN}"; fail=1; fi
done

# Reload: add a name the way Ansible does (write a new file, rename it over
# the old one), then wait for it without restarting the container.
NEW="reloadtest.${DOMAIN}"
started="$(docker inspect -f '{{.State.StartedAt}}' "${NAME}")"
sed "s|^    # Cache responses|    template IN A ${NEW} {\n        answer \"${NEW} 60 IN A 100.64.0.99\"\n    }\n    # Cache responses|" \
  "${OUT}/Corefile" > "${OUT}/Corefile.new"
mv "${OUT}/Corefile.new" "${OUT}/Corefile"
chmod a+r "${OUT}/Corefile"
ok=0
for _ in $(seq 1 15); do
  if resolves "${NEW}"; then ok=1; break; fi
  sleep 2
done
if [ "${ok}" = 1 ] && [ "$(docker inspect -f '{{.State.StartedAt}}' "${NAME}")" = "${started}" ]; then
  echo "PASS  a name added to the Corefile resolves without a restart (reload)"
else
  echo "FAIL  ${NEW} did not resolve after the Corefile changed"; docker logs "${NAME}" 2>&1 | tail -10; fail=1
fi
exit "${fail}"
