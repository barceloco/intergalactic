# Backup strategy

## Why this document exists

The fleet runs stateful services whose data is **not** reproducible from this
ansible repo: relational databases, object storage, and SQLite files. That data
is currently not backed up anywhere. This document defines what must be
protected and how, so the gap is captured and can be closed deliberately rather
than assumed away.

## Current state: the data is not backed up

There is a `backup` role (`ansible/roles/backup/`) and it is written up in
`docs/IMPLEMENTATION_SUMMARY.md`, but it does not protect the data that matters,
for three reasons:

- **It is dormant.** `backup_enabled` is never set (it defaults to `false`) and
  the role is not imported into any playbook, so it does not run on any host.
- **It is config-only.** `scripts/backup-configs.sh` copies CoreDNS and Traefik
  config files and their systemd units. All of those are already reproducible
  from this repo. It does not touch the databases, object storage, or SQLite, and
  it explicitly excludes `acme.json`.
- **It is local-only.** It writes to `/opt/backups` on the same host, so a disk
  failure destroys the backup along with the original.

Treat the existing role as a config-snapshot convenience, not as data
protection. Until the pipeline below is built and enabled, assume the stateful
data is unprotected.

## The principle: 3-2-1

Keep at least three copies of the data, on at least two kinds of media, with at
least one copy off the host. A Raspberry Pi's SSD can fail and take the only copy
with it, so the off-host copy is the non-negotiable part.

## What must be protected

Verify exact volume names on the host before relying on them; the app roles that
create them are the source of truth.

| Data | Roughly where it lives | How to back it up |
|------|------------------------|-------------------|
| Postgres: docgen | `docgen_pgdata` volume on vega | `pg_dump` (logical, portable) |
| Postgres: aispector | `aispector-server_postgres_data` on vega | `pg_dump` |
| Object storage: aispector media | `aispector-server_minio_data` on vega | `mc mirror` the bucket |
| Document storage: docgen | `docgen_doc_storage` volume on vega | `mc mirror` or volume-level copy |
| callosal SQLite | `/srv/callosal/annotations/` on both hosts | `sqlite3 <db> ".backup"` (safe while running) |
| Traefik certificates | `acme.json` in the edge_ingress data dir on rigel | file copy (avoids Let's Encrypt rate limits on restore) |

Redis is a cache and does not need backing up. Grafana dashboards and the
Prometheus config are reproducible from this repo; the Prometheus TSDB (metrics
history) is optional and low priority.

## The recommended pipeline

Run nightly on each host via a systemd timer:

1. Dump each data source into a staging directory: `pg_dump` per database,
   `mc mirror` for object storage, `sqlite3 .backup` for SQLite, and a copy of
   `acme.json`.
2. Push the staging directory off-host with **restic** (encrypted, deduplicated,
   incremental) to:
   - a repo on **mpnas** (the fleet NAS) for fast local restore, and
   - optionally **Backblaze B2** or another S3-compatible target for off-site
     disaster recovery.
3. Prune with a retention policy, for example 7 daily, 4 weekly, 6 monthly.

restic is the recommended tool because it provides encryption, deduplication,
incremental transfer, retention, and off-site targets in a single binary. A
simpler first cut is `pg_dump` plus `rsync` to mpnas, but restic earns its keep
quickly.

## Test restores

A backup that has never been restored is a hope, not a backup. Restore to a
scratch instance on a schedule (quarterly is reasonable), bring the database up,
and confirm the row counts look right. Record that you did it.

## Implementation plan

Build this as an ansible role, either by extending `backup` or adding a new
`app_backups` role, and follow the same guardrails the app roles already use:

1. Store the restic repository password and any B2 credentials in the gitignored
   `all_secrets.yml`. Never commit or print them.
2. Assert each data source exists before dumping, so a misconfigured run cannot
   silently produce an empty backup.
3. Deploy a per-host systemd timer that runs the dump-then-restic pipeline.
4. Wire the role into `vega-production.yml` and `rigel-production.yml`, enabled
   per host with `backup_enabled: true`.
5. Start with the highest-value slice: Postgres dumps to mpnas. Add object
   storage, SQLite, and off-site B2 afterward.
