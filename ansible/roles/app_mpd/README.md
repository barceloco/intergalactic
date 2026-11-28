# app_mpd Role

Deploys mpd (`exnada/mpd`) on rigel in `/srv/mpd`, from its own
`docker/compose.yaml`, as the deploy user. Thin orchestration like
`app_csa`; the repo is only pulled.

## What it does

- Pulls the repo at `mpd_repo_ref` through the `github-mpd` SSH alias.
- Creates `data/raw`, `data/processed` and `data/uploads` (gitignored) and
  never touches their contents.
- Renders `.env` (0600): `COMPOSE_PROJECT_NAME`, `HOST_UID`/`HOST_GID` (the
  deploy user), `MPD_PORT` (8033), `MPD_ADMIN_TOKEN`, plus `mpd_env`.
  Compose gets it with `--env-file`, because the compose file lives in
  `docker/`.
- Adds `restart: unless-stopped` through an override outside the checkout.
- Builds only when the checked-out code changed, starts the `app` service,
  and waits for `/api/health`.

mpd publishes on 127.0.0.1 only: the Traefik route uses
`http://127.0.0.1:8033` (not `http://rigel:8033`, which resolves to
127.0.1.1 on a Pi).

## First deploy

1. Push the first commit to `exnada/mpd`.
2. Run `./scripts/run-ansible.sh prod rigel production --tags services` once
   with `mpd` in `docker_deploy_git_repos`: it prints the github-mpd public
   key. Register it as a read-only deploy key on `exnada/mpd`.
3. Set `mpd_enabled: true` and add the route in `host_vars/rigel.yml`:
   ```yaml
   - host: mpd.exnada.com
     backend: http://127.0.0.1:8033
     health_path: /api/health
   ```
4. `./scripts/run-ansible.sh prod rigel production --tags mpd,dns,edge`.
5. Load the inventory through mpd's admin upload (token: `mpd_admin_token`
   in all_secrets.yml).

## Secrets

`mpd_admin_token` in all_secrets.yml. If `MPD_LLM_PROVIDER=anthropic` is
used, `ANTHROPIC_API_KEY` goes there too and into `mpd_env`.

## License

Proprietary - All Rights Reserved, ExNada Inc.
