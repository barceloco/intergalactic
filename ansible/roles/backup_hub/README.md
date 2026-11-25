# backup_hub

The backup VM (merak). It holds no credentials for any other system and never
pushes anywhere.

- **Pulled by mpnas (Synology).** Account `mpnas-pull` accepts only the listed
  public keys, each forced to `rrsync -ro /mnt` with `restrict` (no shell, no
  forwarding, no PTY). It can read the datasets and nothing else, and write nothing.
- **Daily freshness check** (`backup-hub-check.timer`): alerts through
  `fleet-notify` (role `notify`) when the newest VM backup in `/mnt/vzdump` is
  too old, or when mpnas has not pulled for too long.
- **Off-site USB copy:** `sudo backup-to-usb [-n] <mountpoint>` copies
  `documents`, `immich` and `vzdump` into `<mountpoint>/arcturus/`. It refuses
  unless the target is a mounted dm-crypt (LUKS) filesystem. Unlocking stays
  manual, with the key piped over SSH from the Mac, as for every LUKS drive in
  the fleet.

## Requirements on the host

- The datasets mounted read-only below `/mnt` (virtiofs from arcturus).
- `backup_hub_pull_user` in `ssh_allow_users` (the role checks this).
- Role `notify` for alerts (optional; without it alerts reach the journal only).

## The mpnas side

Synology Hyper Backup's rsync mode cannot use SSH keys, so mpnas pulls with a
scheduled task (Control Panel > Task Scheduler, as root, nightly):

```bash
rsync -aH --delete -e "ssh -i /root/.ssh/arcturus_pull -o IdentitiesOnly=yes" \
  mpnas-pull@merak:/ /volume1/arcturus-backup/
```

(`/` is the root of the read-only view, i.e. merak's `/mnt`.) Put the public
half of `/root/.ssh/arcturus_pull` in `backup_hub_pull_keys`. Protect the target
share with Btrfs data checksums and scheduled, immutable snapshots
(Snapshot Replication), so a compromised arcturus can neither reach nor erase
the history.
