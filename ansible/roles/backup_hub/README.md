# backup_hub

The backup VM (merak). It holds no credentials for any other system and never
pushes anywhere.

- **Pulled by mpnas (Synology).** Account `mpnas-pull` accepts only the listed
  public keys, each forced to `rrsync -ro /mnt` with `restrict` (no shell, no
  forwarding, no PTY). It can read the datasets and nothing else, and write nothing.
- **Daily freshness check** (`backup-hub-check.timer`): alerts through
  `fleet-notify` (role `notify`) when the backup share is not mounted, when a
  VM's newest backup (per id in `backup_hub_vzdump_vmids`) is too old, or when
  mpnas has not logged in for too long. That last check proves a login, not a
  complete transfer: mpnas must report its own rsync failures (below).
- **Off-site USB copy:** `sudo backup-to-usb [-n] <mountpoint>` copies
  `documents`, `immich` and `vzdump` into `<mountpoint>/arcturus/`. It skips,
  and reports as failed, any source that is not a mounted share with its
  `.arcturus-dataset` marker (never mirroring an empty folder). It refuses
  unless the target is a mounted dm-crypt (LUKS) filesystem. Unlocking stays
  manual, with the key piped over SSH from the Mac, as for every LUKS drive in
  the fleet.

## Requirements on the host

- The datasets mounted read-only below `/mnt` (virtiofs from arcturus).
- `backup_hub_pull_user` in `ssh_allow_users` (the role checks this).
- Role `notify` for alerts (optional; without it alerts reach the journal only).

## The mpnas side

Synology Hyper Backup's rsync mode cannot use SSH keys, so mpnas pulls with a
scheduled task (Control Panel > Task Scheduler, as root, nightly). It pulls
each dataset separately, and **only if that dataset's `.arcturus-dataset`
marker is present**: an unmounted share on merak is an empty folder, and
mirroring it with `--delete` would empty the backup.

```bash
#!/bin/bash
# Pull arcturus's datasets from merak (read-only account). Exit non-zero on
# any problem, so the Task Scheduler reports it.
set -u
SSH="ssh -i /root/.ssh/arcturus_pull -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
DEST=/volume1/arcturus-backup
rc=0
for ds in documents immich music audiobooks video vzdump; do
  if ! rsync --list-only -e "${SSH}" "mpnas-pull@merak:/${ds}/.arcturus-dataset" > /dev/null 2>&1; then
    echo "SKIP ${ds}: marker missing on merak (share not mounted?)" >&2
    rc=1
    continue
  fi
  rsync -aH --delete -e "${SSH}" "mpnas-pull@merak:/${ds}/" "${DEST}/${ds}/" || rc=1
done
exit "${rc}"
```

(`/` is the root of the read-only view, i.e. merak's `/mnt`.) Put the public
half of `/root/.ssh/arcturus_pull` in `backup_hub_pull_keys`, and add merak's
host key to `/root/.ssh/known_hosts` on mpnas once, checked by hand. In the
task's settings, enable **"Send run details by email ... only when the script
terminates abnormally"**: merak's daily check only sees that mpnas logged in,
so a pull that fails after logging in is reported here. Protect the target
share with Btrfs data checksums and scheduled, immutable snapshots (Snapshot
Replication), so a compromised arcturus can neither reach nor erase the
history.
