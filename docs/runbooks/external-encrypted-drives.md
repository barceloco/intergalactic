# External Encrypted Drives Runbook

This is how the fleet uses external hard drives. They are LUKS-encrypted,
unlocked and mounted by hand from the operator's machine over SSH, and never
mounted automatically at boot.

This runbook covers two procedures:

1. [Mount a drive that is already encrypted](#1-mount-an-already-encrypted-drive)
2. [Set up a new drive from scratch](#2-set-up-a-new-drive-from-scratch)

Both procedures are automated by `scripts/encrypted-drive.py` (run on the
operator machine; `--dry-run` shows every command first, and the key travels
only on SSH stdin). The manual steps below are the same commands.

```bash
./scripts/encrypted-drive.py --host vega info
./scripts/encrypted-drive.py --host vega setup --serial <SERIAL> --name <NAME> --generate --dry-run
./scripts/encrypted-drive.py --host vega mount --name <NAME> --partuuid <PARTUUID>
./scripts/encrypted-drive.py --host vega umount --name <NAME>
```

The `luks` role only installs `cryptsetup`. It does not open, mount, or store
keys for any drive. Drive keys are **not** kept in this repo.
(`luks_home_passphrase` in `all_secrets.yml` belongs to an internal-partition
feature that was never applied; it is not a drive key.)

## Conventions

| Item | Convention | Example |
|------|------------|---------|
| Drive name | Short label for the drive | `WDD6T` |
| Mount point | `/crypt/<name>` | `/crypt/WDD6T` |
| Mapper name | `dm-<name>` | `/dev/mapper/dm-WDD6T` |
| Device path | `/dev/disk/by-partuuid/<partuuid>` | stable across `/dev/sdX` renames |
| Key | Piped over SSH on stdin, never typed, never on the command line | `printf %s "$key"` |

## Current Drives

| Host | Name | Drive | Notes |
|------|------|-------|-------|
| vega | `WDD6T` | WD 6 TB (WD60NDZW), USB, single `crypto_LUKS` partition | Key held by the operator, outside the repo |
| vega | `WDE6T` | WD 6 TB, USB, single `crypto_LUKS` partition | Key held by the operator, outside the repo |

## Prerequisites

- SSH access to the host as a user with **passwordless sudo**. stdin carries
  the key, so sudo cannot prompt for a password.
- `cryptsetup` on the host (installed by the `luks` role on every host).
- The drive's key, held by the operator in a password manager.

## Key Handling Guarantees

The procedures below are built so that the key:

- **Never travels unencrypted.** It goes from `printf` (a shell builtin, so it
  never appears in the process list) through a local pipe into `ssh`, which
  encrypts it. On the host, `sshd` hands it straight to `cryptsetup` on stdin.
  SSH host key verification ensures it reaches the real host.
- **Is never stored on the host or the drive.** It is not in any command line,
  shell history, or sudo log on the host. `cryptsetup` locks its memory so the
  key cannot be swapped to disk. The drive holds only the LUKS header: the data
  key wrapped under a slow (Argon2) derivation of your key, never the key itself.

Two things remain your responsibility on the operator machine: keep the key in
a password manager or the macOS Keychain rather than in a plain-text script,
and keep the machine's disk encrypted (FileVault).

Commands marked **operator** run on your own machine. Commands marked **host**
run in an SSH session on the host (vega in the examples).

---

## 1. Mount an Already-Encrypted Drive

### Find the PARTUUID (once per drive)

**host:**

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,PARTUUID
```

The partition to use is the one with `FSTYPE` `crypto_LUKS`. Record its
`PARTUUID`; it does not change unless the drive is repartitioned.

### Mount

**operator:**

```bash
user=<user>
host=vega
ssh="ssh ${user}@${host} "

mntpt="WDD6T"
key="<drive key>"        # better: read it from a password manager or Keychain
uuid="<partuuid>"

printf %s "${key}" | ${ssh} "sudo mkdir -p /crypt/${mntpt} && \
    sudo cryptsetup luksOpen /dev/disk/by-partuuid/${uuid} dm-${mntpt} --key-file - && \
    sudo mount /dev/mapper/dm-${mntpt} /crypt/${mntpt}"
```

Use `printf %s`, not `echo`. With `--key-file -`, a trailing newline becomes
part of the key and the unlock fails with "No key available with this passphrase".

### Unmount

**operator:**

```bash
ssh <user>@vega "sudo umount /crypt/WDD6T && sudo cryptsetup close dm-WDD6T"
```

### Check State

**host:**

```bash
lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS   # an open drive shows a child of TYPE crypt
sudo dmsetup ls --target crypt               # empty means nothing is unlocked
findmnt /crypt/WDD6T
```

---

## 2. Set Up a New Drive from Scratch

This destroys everything on the drive. It produces a drive that the procedure
in section 1 mounts unchanged: one GPT partition, LUKS2, ext4 inside.

### Step 1: Identify the drive

**host:** Run `lsblk` before and after plugging the drive in; the new entry is
the drive.

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,MOUNTPOINTS
findmnt -no SOURCE /          # the system disk: never touch this one
ls -l /dev/disk/by-id/ | grep -v part
```

Match the serial in `/dev/disk/by-id/` against the label on the drive. From
here on, refer to the drive **only** by that by-id path, never by `/dev/sdX`:

```bash
disk=/dev/disk/by-id/usb-<MODEL>_<SERIAL>-0:0   # the whole disk, no -partN
```

If the drive auto-mounted, unmount every partition on it first
(`sudo umount ${disk}-part1`, and so on).

### Step 2: Choose a name

Pick a short name, such as `WDD6T`. It becomes the mount point
`/crypt/<name>`, the mapper name `dm-<name>`, and the filesystem label.

### Step 3: Generate and store the key

**operator:** Use your password manager's generator to create a random
64-character password, and save it under the drive's name **before going
further**. Generating it there means the key never appears on screen or in a
file. LUKS keys cannot be recovered: lose the key and the data is gone.

### Step 4: Wipe and partition

**host:**

```bash
lsblk "${disk}"                          # last check: is this the right drive?
sudo wipefs -a "${disk}"-part* 2>/dev/null; sudo wipefs -a "${disk}"
printf 'label: gpt\n,,L\n' | sudo sfdisk "${disk}"
sudo udevadm settle
```

`sfdisk` creates a GPT partition table with a single Linux partition spanning
the whole drive.

### Step 5: Record the PARTUUID

**host:**

```bash
lsblk -no PARTUUID "${disk}-part1"
```

Store the PARTUUID next to the key in your password manager. Every later step
addresses the partition through `/dev/disk/by-partuuid/<partuuid>`, which only
exists for the partition you just created.

### Step 6: Encrypt

**operator:**

```bash
user=<user>
host=vega
ssh="ssh ${user}@${host} "

mntpt="WDD6T"
key="<drive key>"
uuid="<partuuid>"

printf %s "${key}" | ${ssh} "sudo cryptsetup luksFormat --type luks2 --batch-mode \
    /dev/disk/by-partuuid/${uuid} --key-file -"
```

`--batch-mode` skips the interactive "Type YES" confirmation, which cannot work
while stdin carries the key. Steps 1 and 4 are the safety check, and the
PARTUUID path guarantees this can only hit the new partition.

### Step 7: Create the filesystem and mount

**operator** (same variables as step 6):

```bash
printf %s "${key}" | ${ssh} "sudo cryptsetup luksOpen /dev/disk/by-partuuid/${uuid} dm-${mntpt} --key-file - && \
    sudo mkfs.ext4 -L ${mntpt} -m 0 /dev/mapper/dm-${mntpt} && \
    sudo mkdir -p /crypt/${mntpt} && \
    sudo mount /dev/mapper/dm-${mntpt} /crypt/${mntpt}"
```

`-m 0` drops ext4's 5% root reservation, which on a data-only drive is wasted
space (300 GB on a 6 TB drive). Formatting a large drive takes a few minutes.

The new filesystem is owned by root. To let a user write to it:

```bash
ssh <user>@vega "sudo chown <owner>:<owner> /crypt/WDD6T"
```

### Step 8: Back up the LUKS header

The LUKS header holds the key slots. If it is damaged, the whole drive is
unreadable even with the right key. Keep a copy off the drive.

**operator:**

```bash
${ssh} "sudo cryptsetup luksHeaderBackup /dev/disk/by-partuuid/${uuid} \
    --header-backup-file /dev/shm/${mntpt}.luksheader && sudo chown ${user} /dev/shm/${mntpt}.luksheader"
scp ${user}@${host}:/dev/shm/${mntpt}.luksheader .
${ssh} "rm /dev/shm/${mntpt}.luksheader"
```

`/dev/shm` is RAM-backed, so the copy never touches the host's disk.

Store `<name>.luksheader` alongside the key. The header is protected by the key
but is still sensitive: anyone holding both can read the drive.

### Step 9: Verify with a clean remount

Unmount and close the drive, then mount it again with the exact procedure in
[section 1](#1-mount-an-already-encrypted-drive). This proves that the stored
key and PARTUUID work before any data goes on the drive.

### Step 10: Record the drive

Add a row to [Current Drives](#current-drives) above: host, name, model, and
where the key lives. Never add the key or the PARTUUID to this repo.

---

## Troubleshooting

| Error | Cause and fix |
|-------|---------------|
| `No key available with this passphrase` | Wrong key, or extra bytes such as a trailing newline. Use `printf %s`. |
| `Device dm-WDD6T already exists` | Already unlocked, often after a failed `mount`. Mount it, or `sudo cryptsetup close dm-WDD6T` and retry. |
| `sudo: a terminal is required` / `a password is required` | The SSH user lacks passwordless sudo. |
| `/dev/disk/by-partuuid/...: No such file` | Wrong PARTUUID, or udev has not caught up. Run `sudo udevadm settle` and re-check with `lsblk -o NAME,PARTUUID`. |
| `luksFormat` or `luksOpen` killed, or out of memory | LUKS2's Argon2 key derivation can use up to 1 GB of RAM. On small hosts (Pi 3 and older), add `--pbkdf-memory 262144` to `luksFormat`. |
| Drive missing after reboot | Expected. Mounts are manual and not persistent; run section 1 again. |
