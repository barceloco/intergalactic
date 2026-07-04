---
name: deploy-fleet-app
description: >-
  Deploy a new application or service to the Raspberry Pi fleet (hosts vega and
  rigel) managed by the intergalactic Ansible repo, and expose it at a subdomain
  such as csa.exnada.com. Use this when adding a reverse-proxy route, mapping a
  subdomain to a backend, onboarding a new app repo, opening a service port, or
  anyone asks how to deploy something to vega or rigel. Covers the mandatory
  per-host port-conflict check, automatic DNS, wildcard TLS, the firewall, and
  the exact deploy commands.
---

# Deploy a new app to the fleet (vega / rigel)

This skill deploys an arbitrary application to the intergalactic-managed Pi fleet
and exposes it at `https://<name>.<domain>`. It is app-agnostic: `<name>`,
`<repo>`, `<host>`, `<port>`, and `<domain>` are inputs you fill in. The running
example is `csa` -> `csa.exnada.com`, but nothing here is specific to csa.

## 0. Orient first (do not skip)

- All changes and deploy commands happen in the **intergalactic** Ansible repo.
  It is typically at `~/Documents/GitHub/intergalactic`, but confirm the path
  rather than assuming. Every path below is relative to that repo root.
- Only the intergalactic repo is edited. The app's own source repo is at most
  pulled (read); it is never committed to or modified from here.
- Hosts: **rigel** is the edge (runs Traefik and CoreDNS, the single public
  entrypoint). **vega** is the main service host. Apps usually run on vega;
  rigel can host apps too.
- You MUST be on the fleet's Tailscale network for any production deploy. The
  production playbook enforces this and will refuse otherwise.

## Mental model: how a request reaches an app

`https://csa.exnada.com`
-> CoreDNS resolves it to **rigel** (auto-derived from the route)
-> **Traefik on rigel** terminates TLS using the `*.exnada.com` wildcard cert
-> proxies to the backend `http://<host>:<port>` across Tailscale.

Four things must line up: (1) the app runs on `<host>:<port>`, (2) that port is
open in `<host>`'s firewall, (3) a route exists on rigel, and (4) DNS + TLS,
which are automatic once the route exists.

## Inputs to collect up front

- Subdomain / app name: `<name>` (for example `csa` -> `csa.exnada.com`)
- Where it runs: `<host>` = `vega` (default) or `rigel`
- Backend port: `<port>` -- must be free on `<host>`; see Step 1
- Source repo URL, only if ansible should deploy the app itself
- Any config or secrets the app needs

## Step 1 -- Choose the host and the port

### 1a. Derive a deterministic port from the app name

Give each app a host port that depends only on its name, so the same app gets
the SAME port on rigel and vega and different apps usually differ. Formula:

    host_port = <app's internal container port, usually 8000> + letter_sum(name)

`letter_sum` adds each letter's alphabet position (A=1, B=2, ... Z=26),
uppercased, with non-letters ignored. Example: `abc` from internal port 8000 is
8000 + (1 + 2 + 3) = 8006; `csa` is 8023.

```bash
derive_port() {  # usage: derive_port <name> [internal_port, default 8000]
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z' | awk -v b="${2:-8000}" '{
    s=0; for (i=1;i<=length($0);i++) s+=index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", substr($0,i,1));
    print b + s
  }'
}
derive_port csa            # -> 8023
derive_port myapp 3000     # -> pass the app's real internal port if it is not 8000
```

This is a deterministic SUGGESTION, not a guarantee of uniqueness. The sum is
order-independent, so anagrams collide (`ab` and `ba` both give 8003), and a
derived value can also land on an already-used or grandfathered port. Treat it
as the default candidate, then verify it is actually free in 1b. Existing apps
keep their current ports (aispector 8000, callosal 8001, docgen 8420); the
derivation is only for new apps.

### 1b. Verify the candidate port is free on the host (mandatory)

NEVER assume the derived port is free. Check the target host three independent
ways; if the candidate appears in any, move to the next free port (for example
+1, then re-check) and note the deviation from the derived value.

1. Ports already declared for the host, in the repo:
   ```bash
   grep -nE 'firewall_allow_tcp_ports|docker_deploy_tcp_ports' -A20 \
     ansible/inventories/prod/host_vars/<host>.yml
   # backends already pointed at this host:
   grep -nE "backend:.*<host>:" ansible/inventories/prod/host_vars/rigel.yml
   ```
2. Ports actually listening on the host right now:
   ```bash
   ssh <host> "sudo ss -tlnp | grep LISTEN | awk '{print \$4}' | grep -oE '[0-9]+$' | sort -un"
   ```
3. Ports published by running containers:
   ```bash
   ssh <host> "sudo docker ps --format '{{.Names}}: {{.Ports}}'"
   ```

Known usage at time of writing (verify live, do not trust this list):
- vega: 8000 aispector, 8001 callosal, 8420 docgen
- rigel: 8000 dev, 8001 demo, plus DB ports 5432 / 6379 / 9000 / 9001

`ansible/inventories/prod/group_vars/ports.yml` lists *named* ports
(`port_api: 8000`, `port_api_alt: 8001`, ...), but those names are reused across
hosts, so ports.yml is NOT a free-port registry. The per-host live check above
is authoritative.

## Step 2 -- Deploy the app itself

Two patterns; prefer the first.

**A. Ansible-managed (recommended).** Copy the `app_docgen` role at
`ansible/roles/app_docgen/` as your template. It is a thin orchestration role
that, as the `deploy` user: pulls the app repo at a ref (read only), renders any
gitignored `.env` from a template, and runs the app's own build/run (its
Makefile or `docker compose`). Non-negotiable guardrails to keep from the
template:
- Never manage the app's data volumes. If it has a named DB volume, assert it
  exists before starting, so a redeploy can never silently create an empty DB.
- Prove the first run against a live instance is a no-op before trusting it
  (render the `.env`, diff against the live file, confirm no container recreate).
- Derive the deploy-time health-check port from the app's configured port
  (e.g. `{{ app_env.APP_PORT | default('8000') }}`), NEVER a hardcoded literal,
  or a later port move silently checks the wrong port (this bit docgen).
- Build only when the checked-out code changed: register the git result and gate
  `docker compose build` on `.changed`; then `up -d` reuses the image. `--build`
  every run needlessly rebuilds and recreates the container.

**App-side prerequisites -- check both BEFORE you start (both bit csa):**
1. **Configurable host port.** The app's compose must publish
   `"${APP_PORT:-<internal>}:<internal>"`, not a hardcoded port, so ansible can
   choose a non-conflicting host port via the gitignored `.env`. If it hardcodes
   the port, that one line is the *only* change you should need in the app repo
   (ask the owner first; it is backward compatible).
2. **A restart policy** (required for auto-restart after a power loss -- see the
   Definition of done). The container needs `restart: unless-stopped` (or
   `always`). If the app's compose declares none, do NOT edit the repo -- add it
   via an ansible-managed compose *override* kept OUTSIDE the checkout:
   `docker compose -f compose.yaml -f <override> up -d`, where the override sets
   `services.<svc>.restart: unless-stopped`. See `app_csa` for the pattern.

Also: ansible must be able to `become` the `deploy` user, which needs the `acl`
package (setfacl) on the host. It is in the `common` role, so a host that has
run foundation has it; a brand-new host needs foundation first.

Wire the role into `<host>-production.yml`. On **vega** specifically, add it to
the `tasks:` section AFTER the `git_ssh` import (so the deploy user's SSH
aliases exist before the app repo is pulled), and do NOT run the full
`docker_deploy` role on vega (see Gotchas: vega's `/srv`).

If the app repo is pulled by the `deploy` user, also add its short name to
`docker_deploy_git_repos` in `<host>.yml`, deploy once, and register the public
key the role prints as a GitHub **deploy key** on the app repo. Deploy keys are
unique per repo AND per host.

**B. Self-deployed.** If the app is already deployed by its own tooling and you
only need to expose it, skip the role and do Steps 3-4 only.

## Step 3 -- Open the firewall port

In `ansible/inventories/prod/host_vars/<host>.yml`, add `<port>` to the host's
firewall port list. Use whichever list the host already uses: hosts running the
full `docker_deploy` role (e.g. **rigel**) declare service ports in
`docker_deploy_tcp_ports`, which the firewall role auto-merges into the allowed
ports; hosts without it use `firewall_allow_tcp_ports` directly.

```yaml
docker_deploy_tcp_ports:    # or firewall_allow_tcp_ports on hosts without docker_deploy
  - ...
  - <port>   # <name> -> <name>.<domain>
```

The firewall is a FOUNDATION role, so opening a port takes a separate
`run-ansible.sh prod <host> foundation --tags security` run (over Tailscale),
not the production run. This lets Traefik on rigel reach the app over Tailscale.

## Step 4 -- Add the edge route (this is what gives you DNS and TLS for free)

In `ansible/inventories/prod/host_vars/rigel.yml`, add ONE entry to
`edge_ingress_routes`:

```yaml
  - host: <name>.<domain>
    backend: http://<host>:<port>
    health_path: /health      # optional; omit if the app has no health endpoint
```

That single entry does three things automatically:
- Creates the Traefik HTTPS router for `<name>.<domain>`.
- Is covered by the existing `*.<domain>` wildcard certificate. No per-domain
  ACME, no cert step.
- Creates the CoreDNS record: the `internal_dns` role extracts the subdomain
  from each route and points it at rigel. Do NOT also list it in
  `internal_dns_private_hosts`; routed hosts are added automatically and listing
  it twice is an error.

## Step 5 -- Secrets (only if the app needs them)

Never commit secrets and never print their values. Put them in the gitignored
`ansible/inventories/prod/group_vars/all_secrets.yml` and reference them from
host_vars with `{{ var_name }}`. Append to that file without reading its other
contents. Example: docgen's admin allow-list lives there as `docgen_admins`,
referenced from `host_vars/vega.yml`.

## Step 6 -- Deploy

```bash
# the app and its firewall port (run this if the app runs on vega)
./scripts/run-ansible.sh prod <host> production
# the edge route and DNS (always, because the route lives on rigel)
./scripts/run-ansible.sh prod rigel production
```

Both are idempotent; run only what changed. You can scope with `--tags services`
(the service roles) or an app role's own tag (for example app_docgen is
reachable via `--tags docgen`).

## Step 7 -- Verify (not done until all three hold)

1. **Reachable through the edge:** from a Tailscale-connected machine,
   `curl -sS -o /dev/null -w "%{http_code}\n" https://<name>.<domain>` returns
   200; also `./scripts/verify-reverse-proxy.sh rigel`.
2. **Right port on the right host:** the container publishes `<port>-></internal>`
   on `<host>`.
3. **Auto-restarts after power loss:** the container's restart policy is
   `unless-stopped` (or `always`) and Docker is enabled on boot -- otherwise it
   will NOT come back after a reboot (fix with the Step 2 restart override):
   ```bash
   ssh <host> "sudo docker inspect <container> --format '{{.HostConfig.RestartPolicy.Name}}'"  # want: unless-stopped
   ssh <host> "systemctl is-enabled docker"                                                    # want: enabled
   ```

## Gotchas (each of these has bitten someone)

- **Tailscale is required** for production deploys; the playbook enforces it.
- **`--check` is broken here.** Check mode skips the ssh-keyscan command, so
  host-key verification fails with UNREACHABLE. Do not verify with `--check`;
  verify with real idempotent runs and acceptance tests (a clean re-run reports
  no changes).
- **Data volumes are sacred.** Never `docker compose down -v`. Assert a DB
  volume exists before bringing a stack up.
- **vega's `/srv` is a real directory**, and the full `docker_deploy` role
  bind-mounts `/srv`, which would shadow the live app repos. On vega, import
  only the tasks you need (see how `vega-production.yml` imports `git_ssh`), not
  the whole role.
- **The wildcard cert** `*.<domain>` already covers new subdomains. There is no
  certificate step for a new route.
- **Deploys no longer bounce Docker**, but historically a careless firewall or
  docker_host change would restart Docker and drop the edge containers. Keep
  edge units on `Wants=docker.service`, not `Requires=`.
- **SMB/NetBIOS names cap at 15 characters**, so an FQDN cannot be used for SMB;
  use a short host name for file shares.
- **Never read or commit credentials.** Treat secret files as write-only from
  ansible's side; keep values in the gitignored all_secrets.yml.
- **First deploy of a new route can fail DNS validation on the first pass.** The
  Corefile change notifies a play-end handler and CoreDNS has no reload plugin,
  so a brand-new host is not served yet when validation runs. The `internal_dns`
  role now self-heals (restarts CoreDNS and re-tests when a host is unresolved);
  seeing it restart CoreDNS mid-validation is expected, not an error.
- **`acl` must be on the host** for ansible to `become` the deploy user
  (setfacl). It is in the `common` role; a host that has not run foundation will
  fail app roles with a `chmod: invalid mode` ACL error until foundation runs.
- **Match the app's own health path.** The deploy gate and the route's
  `health_path` should use whatever the app actually serves (the fleet uses
  `/health`). If an app has no health endpoint, omit `health_path` and use a
  looser deploy gate (accept 200/403/404 = "app is up"), like app_docgen.

## Worked example: csa -> csa.exnada.com on rigel (actually done)

1. **Port:** `derive_port csa` -> `8023` (8000 + 3 + 19 + 1); verified free on
   rigel (Step 1b).
2. **App-side prereqs:** csa's compose hardcoded `8000:8000` (fix: one line ->
   `${CSA_PORT:-8000}:8000`, the only csa-repo change, owner-approved) and had no
   restart policy (fix: an ansible override adds `restart: unless-stopped`, no
   repo change).
3. **Role:** `app_csa` copied from `app_docgen` -- pulls the repo, renders `.env`
   with `CSA_PORT=8023`, runs `docker compose -f compose.yaml -f <override>
   up -d`, builds only on code change, health-gates `/health`.
4. **Deploy key:** add `csa` to rigel's `docker_deploy_git_repos`, run production
   once to generate the key, register the printed pubkey as a read-only deploy
   key on the (private) ExNada/csa repo.
5. **Firewall:** `host_vars/rigel.yml` -> `docker_deploy_tcp_ports: - 8023`;
   apply with `run-ansible.sh prod rigel foundation --tags security`.
6. **Route:** `host_vars/rigel.yml` -> `edge_ingress_routes: - host:
   csa.exnada.com / backend: http://rigel:8023 / health_path: /health`.
7. **Deploy + verify:** `run-ansible.sh prod rigel production`, then all three
   Step 7 checks (200; publishes 8023; restart=unless-stopped + docker enabled).
