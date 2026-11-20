#!/usr/bin/env python3
"""Set up, mount, and unmount LUKS-encrypted external drives on a fleet host over SSH.

Run this on your own machine. The drive key never leaves it except inside the
SSH channel: it is read here (hidden prompt, macOS Keychain, or freshly
generated onto the clipboard), written to ssh's stdin, and handed by sshd
straight to cryptsetup's stdin on the host. It is never put on a command line,
printed, written to a file, or stored on the host or the drive.

Subcommands:
  info     list the host's disks (read-only)
  setup    wipe, partition, encrypt, format, and mount a NEW drive (destructive)
  mount    unlock and mount an existing drive
  umount   unmount and lock a drive

Examples:
  ./encrypted-drive.py --host vega info
  ./encrypted-drive.py --host vega setup --serial <SERIAL> --name WDE6T --generate --dry-run
  ./encrypted-drive.py --host vega setup --serial <SERIAL> --name WDE6T --generate \\
      --owner <user> --header-backup WDE6T.luksheader
  ./encrypted-drive.py --host vega setup --serial <SERIAL> --name WDE6T --like <WDD6T-PARTUUID> \\
      --key-env WDE6T_KEY --env-file ~/secure/drives.env
  ./encrypted-drive.py --host vega mount --name WDE6T --partuuid <PARTUUID> --keychain luks-WDE6T
  ./encrypted-drive.py --host vega umount --name WDE6T

Conventions (docs/runbooks/external-encrypted-drives.md): mount point
/crypt/<name>, mapper /dev/mapper/dm-<name>, partition addressed by PARTUUID.

Requirements: Python 3.8+ (stdlib only); SSH key access to the host as a user
with passwordless sudo; cryptsetup on the host (installed by the luks role).
"""
from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import secrets
import shlex
import subprocess
import sys

NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$")
MIN_KEY_LEN = 32
q = shlex.quote


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


class Host:
    """Runs commands on the host over SSH. Remote command strings never contain the key."""

    def __init__(self, dest: str, ssh_cmd: str, dry_run: bool) -> None:
        self.dest = dest
        self.ssh = shlex.split(ssh_cmd)
        self.dry_run = dry_run

    def run(self, remote: str, *, key: str | None = None, capture: bool = False,
            mutating: bool = True) -> bytes:
        if self.dry_run and mutating:
            print(f"[dry-run] {self.dest}: {remote}" + ("    <- key on stdin" if key is not None else ""))
            return b""
        argv = self.ssh + ["-o", "BatchMode=yes", self.dest, remote]
        kwargs = {"input": key.encode()} if key is not None else {"stdin": subprocess.DEVNULL}
        proc = subprocess.run(argv, stdout=subprocess.PIPE if capture else None, **kwargs)
        if proc.returncode != 0:
            die(f"remote command failed (exit {proc.returncode}): {remote}")
        return proc.stdout or b""

    def text(self, remote: str) -> str:
        return self.run(remote, capture=True, mutating=False).decode()


# ---------------------------------------------------------------- disk discovery

def disks(host: Host) -> list[dict]:
    out = host.text("lsblk -J -b -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN,TYPE,FSTYPE,LABEL,PTUUID,PARTUUID,MOUNTPOINTS")
    return [d for d in json.loads(out)["blockdevices"] if d.get("type") == "disk"]


def mountpoints(dev: dict) -> list[str]:
    found = [m for m in (dev.get("mountpoints") or []) if m]
    for child in dev.get("children") or []:
        found += mountpoints(child)
    return found


def human(size: int | str | None) -> str:
    n = float(size or 0)
    for unit in ("B", "K", "M", "G", "T"):
        if n < 1024 or unit == "T":
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}T"


def find_by_serial(host: Host, serial: str) -> dict:
    matches = [d for d in disks(host) if (d.get("serial") or "").strip() == serial]
    if not matches:
        die(f"no disk with serial {serial!r} on {host.dest}; run 'info' to list disks")
    if len(matches) > 1:
        die(f"{len(matches)} disks report serial {serial!r}; refusing to guess")
    return matches[0]


def by_id_path(host: Host, kpath: str, serial: str) -> str:
    out = host.text('for f in /dev/disk/by-id/*; do printf "%s %s\\n" "$f" "$(readlink -f "$f")"; done')
    links = [ln.split(" ", 1)[0] for ln in out.splitlines()
             if ln.endswith(" " + kpath) and "-part" not in ln.split(" ", 1)[0]]
    if not links:
        die(f"no /dev/disk/by-id link for {kpath}")
    links.sort(key=lambda p: (serial not in p, not os.path.basename(p).startswith("usb-")))
    return links[0]


# ---------------------------------------------------------------- encryption parameters

PARAM_RE = re.compile(r"^[A-Za-z0-9:_-]+$")


def parse_luks_dump(text: str) -> list[str]:
    """Turn `cryptsetup luksDump` output into luksFormat options that reproduce it.

    Copies the LUKS version, data cipher, data key size, sector size (LUKS2),
    PBKDF type (LUKS2), and hash. luksDump never contains a key. PBKDF cost
    (time/memory) is not copied: cryptsetup benchmarks it for the host.
    """
    fields: dict = {}
    section = None
    for raw in text.splitlines():
        line = raw.strip()
        if raw and not raw[0].isspace() and line.endswith(":"):
            section = line[:-1]
            continue
        k, sep, v = line.partition(":")
        if sep:
            fields.setdefault((section, k.strip()), v.strip())  # first entry wins: segment 0, keyslot 0, digest 0

    def get(sec, field):
        v = fields.get((sec, field))
        if not v:
            die(f"could not find '{field}' in the reference drive's luksDump")
        return v.split()[0]  # drop units such as "bits" or "[bytes]"

    version = get(None, "Version")
    if version == "2":
        opts = ["--type", "luks2",
                "--cipher", get("Data segments", "cipher"),
                "--key-size", get("Keyslots", "Key"),
                "--sector-size", get("Data segments", "sector"),
                "--pbkdf", get("Keyslots", "PBKDF"),
                "--hash", get("Digests", "Hash")]
    elif version == "1":
        opts = ["--type", "luks1",
                "--cipher", f"{get(None, 'Cipher name')}-{get(None, 'Cipher mode')}",
                "--key-size", get(None, "MK bits"),
                "--hash", get(None, "Hash spec")]
    else:
        die(f"unsupported LUKS version {version!r} on the reference drive")
    for o in opts:
        if not PARAM_RE.match(o):
            die(f"unexpected value {o!r} in the reference drive's luksDump")
    return opts


def luks_params_like(host: Host, ref: str) -> list[str]:
    dev = f"/dev/disk/by-partuuid/{ref}" if UUID_RE.match(ref) else ref
    if not dev.startswith("/dev/"):
        die("--like takes a PARTUUID or a /dev/... path")
    dump = host.text(f"sudo -n cryptsetup isLuks {q(dev)} || {{ echo '{dev} is not a LUKS device' >&2; exit 1; }}; "
                     f"sudo -n cryptsetup luksDump {q(dev)}")
    return parse_luks_dump(dump)


# ---------------------------------------------------------------- key handling

def env_file_value(path: str, var: str) -> str | None:
    """Return VAR from a .env file (VAR=value or export VAR=value; optional quotes).
    The file is not sourced and nothing from it is ever printed."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError as e:
        die(f"cannot read {path}: {e.strerror}")
    for line in lines:
        line = line.strip()
        if line.startswith("export "):
            line = line[len("export "):].lstrip()
        name, sep, value = line.partition("=")
        if sep and name.strip() == var:
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            return value
    return None


def read_key(args: argparse.Namespace, *, new: bool) -> str:
    if getattr(args, "key_env", None):
        var = args.key_env
        key = env_file_value(args.env_file, var) if args.env_file else os.environ.get(var)
        if key is None:
            where = args.env_file or "the environment"
            die(f"variable {var} is not set in {where}")
    elif getattr(args, "keychain", None):
        r = subprocess.run(["security", "find-generic-password", "-s", args.keychain, "-w"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if r.returncode != 0:
            die(f"no Keychain item with service name {args.keychain!r}")
        key = r.stdout.decode().rstrip("\n")
    elif new and getattr(args, "generate", False):
        key = secrets.token_hex(32)
        subprocess.run(["pbcopy"], input=key.encode(), check=True)
        print("A new 64-character key is on your clipboard (not shown).")
        print("Paste it into your password manager now.")
        answer = input("Type 'saved' once it is stored (anything else aborts; nothing has been changed yet): ")
        subprocess.run(["pbcopy"], input=b"", check=True)  # clear the clipboard either way
        if answer.strip() != "saved":
            die("aborted before touching the drive")
    else:
        key = getpass.getpass("Drive key (hidden): ")
        if new and getpass.getpass("Repeat key (hidden): ") != key:
            die("keys do not match")
    if not key:
        die("empty key")
    if "\n" in key:
        die("key contains a newline")
    if new and len(key) < MIN_KEY_LEN and not args.allow_short_key:
        die(f"key shorter than {MIN_KEY_LEN} characters; use --generate or --allow-short-key")
    return key


# ---------------------------------------------------------------- subcommands

def cmd_info(host: Host, args: argparse.Namespace) -> None:
    for d in disks(host):
        mounts = mountpoints(d)
        flag = "  <- in use, mounted: " + ", ".join(mounts) if mounts else ""
        print(f"{d['path']:<14} {human(d.get('size')):>8}  tran={d.get('tran') or '-':<5} "
              f"model={d.get('model') or '-'}  serial={d.get('serial') or '-'}{flag}")
        for c in d.get("children") or []:
            print(f"   {c['path']:<14} {human(c.get('size')):>8}  fstype={c.get('fstype') or '-'}  "
                  f"label={c.get('label') or '-'}  partuuid={c.get('partuuid') or '-'}")


def cmd_setup(host: Host, args: argparse.Namespace) -> None:
    name, mapper, mnt = args.name, f"dm-{args.name}", f"/crypt/{args.name}"
    host.text("command -v cryptsetup >/dev/null || { echo 'cryptsetup missing (run the luks role)' >&2; exit 1; }")
    taken = host.text(f"if [ -e /dev/mapper/{q(mapper)} ] || mountpoint -q {q(mnt)} 2>/dev/null; then echo taken; fi")
    if taken.strip():
        die(f"{mapper} or {mnt} is already in use on {host.dest}; pick another --name")

    d = find_by_serial(host, args.serial)
    if mountpoints(d):
        die(f"{d['path']} has mounted filesystems ({', '.join(mountpoints(d))}); refusing")
    if d.get("tran") != "usb" and not args.allow_non_usb:
        die(f"{d['path']} is not a USB disk (tran={d.get('tran')}); use --allow-non-usb if intended")
    disk = by_id_path(host, d["path"], args.serial)
    parts = [c["path"] for c in d.get("children") or []]
    fmt_opts = luks_params_like(host, args.like) if args.like else ["--type", "luks2"]

    print(f"\nTarget on {host.dest}:")
    print(f"  {disk}")
    print(f"  = {d['path']}, {human(d.get('size'))}, model {d.get('model')}, serial {d.get('serial')}")
    print(f"  existing partitions: {', '.join(parts) or 'none'}")
    print(f"  encryption: {' '.join(fmt_opts)}" + (f"  (copied from {args.like})" if args.like else ""))
    print(f"ALL DATA ON THIS DRIVE WILL BE DESTROYED. It becomes {name}, mounted at {mnt}.\n")
    if input("Type the drive serial to confirm: ").strip() != args.serial:
        die("confirmation did not match; nothing was changed")

    key = "<not read in dry-run>" if host.dry_run else read_key(args, new=True)

    print("\n== Wiping and partitioning")
    wipe = [f"sudo -n wipefs -a {q(p)}" for p in parts] + [f"sudo -n wipefs -a {q(disk)}"]
    host.run("set -e; " + "; ".join(wipe) +
             f"; printf 'label: gpt\\n,,L\\n' | sudo -n sfdisk --quiet {q(disk)}; sudo -n udevadm settle")

    if host.dry_run:
        ptuuid, partuuid = "<ptuuid>", "<partuuid>"
    else:
        d = find_by_serial(host, args.serial)
        children = d.get("children") or []
        ptuuid = d.get("ptuuid") or ""
        partuuid = (children[0].get("partuuid") or "") if len(children) == 1 else ""
        if not UUID_RE.match(ptuuid) or not UUID_RE.match(partuuid):
            die("partitioning did not produce exactly one GPT partition; inspect with 'info'")
    part = f"/dev/disk/by-partuuid/{partuuid}"
    host.run(f"sudo -n udevadm settle; test -b {q(part)}")

    print(f"== Encrypting ({' '.join(fmt_opts)})")
    host.run(f"sudo -n cryptsetup luksFormat {' '.join(q(o) for o in fmt_opts)} --batch-mode {q(part)} --key-file -",
             key=key)

    print("== Unlocking, creating ext4, mounting")
    host.run(f"sudo -n cryptsetup luksOpen {q(part)} {q(mapper)} --key-file -", key=key)
    owner = f"; sudo -n chown {q(args.owner)}:{q(args.owner)} {q(mnt)}" if args.owner else ""
    host.run(f"set -e; sudo -n mkfs.ext4 -L {q(name)} -m 0 /dev/mapper/{q(mapper)}; "
             f"sudo -n mkdir -p {q(mnt)}; sudo -n mount /dev/mapper/{q(mapper)} {q(mnt)}{owner}")

    if args.header_backup:
        print(f"== Backing up the LUKS header to {args.header_backup}")
        remote = (f"set -e; f=/dev/shm/{q(name)}.luksheader; trap 'sudo -n rm -f \"$f\"' EXIT; "
                  f"sudo -n rm -f \"$f\"; sudo -n cryptsetup luksHeaderBackup {q(part)} --header-backup-file \"$f\"; "
                  f"sudo -n cat \"$f\"")
        data = host.run(remote, capture=True)
        if not host.dry_run:
            fd = os.open(args.header_backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as fh:
                fh.write(data)

    print("== Verifying with a clean lock, unlock, and mount")
    host.run(f"set -e; sudo -n umount {q(mnt)}; sudo -n cryptsetup close {q(mapper)}")
    host.run(f"sudo -n cryptsetup luksOpen {q(part)} {q(mapper)} --key-file -", key=key)
    host.run(f"sudo -n mount /dev/mapper/{q(mapper)} {q(mnt)}")
    if not host.dry_run:
        label = host.text(f"lsblk -no LABEL /dev/mapper/{q(mapper)}").strip()
        if label != name:
            die(f"verification failed: filesystem label is {label!r}, expected {name!r}")
    del key

    print(f"\nDone. {name} is mounted at {mnt} on {host.dest}.\n")
    print_snippets(name, d, ptuuid, partuuid)


def cmd_mount(host: Host, args: argparse.Namespace) -> None:
    mapper, mnt = f"dm-{args.name}", f"/crypt/{args.name}"
    part = f"/dev/disk/by-partuuid/{args.partuuid}"
    if host.text(f"if mountpoint -q {q(mnt)} 2>/dev/null; then echo yes; fi").strip():
        print(f"{mnt} is already mounted on {host.dest}")
        return
    host.text(f"test -b {q(part)} || {{ echo 'no partition with that PARTUUID is attached' >&2; exit 1; }}")
    key = "<not read in dry-run>" if host.dry_run else read_key(args, new=False)
    host.run(f"set -e; sudo -n mkdir -p {q(mnt)}; "
             f"if [ ! -e /dev/mapper/{q(mapper)} ]; then sudo -n cryptsetup luksOpen {q(part)} {q(mapper)} --key-file -; fi; "
             f"sudo -n mount /dev/mapper/{q(mapper)} {q(mnt)}", key=key)
    del key
    print(f"{args.name} mounted at {mnt} on {host.dest}")


def cmd_umount(host: Host, args: argparse.Namespace) -> None:
    mapper, mnt = f"dm-{args.name}", f"/crypt/{args.name}"
    host.run(f"set -e; if mountpoint -q {q(mnt)}; then sudo -n umount {q(mnt)}; fi; "
             f"if [ -e /dev/mapper/{q(mapper)} ]; then sudo -n cryptsetup close {q(mapper)}; fi")
    print(f"{args.name} unmounted and locked on {host.dest}")


def print_snippets(name: str, d: dict, ptuuid: str, partuuid: str) -> None:
    site = {name: {
        "type": "<e.g. Western Digital Elements 6TB>",
        "partnumber": d.get("model") or "",
        "serialnumber": d.get("serial") or "",
        "diskid": ptuuid,
        "partitions": {"1": {
            "partuuid": partuuid, "target": name, "mode": "luks", "IV": "plain64",
            "key": "<paste the key from your password manager>", "notes": "",
        }},
    }}
    area = {name: {"mountpoint": "crypt", "territory": name, "partition": "1"}}
    print('For secret_map.json, inside "site" (comma after the previous entry):')
    print(json.dumps(site, indent="\t")[2:-2])
    print('\nInside "area" -> "<host>" (comma after the previous entry):')
    print(json.dumps(area, indent="\t")[2:-2])
    print("\nTo mount later (key from Keychain or a hidden prompt):")
    print(f"  ./encrypted-drive.py --host <host> mount --name {name} --partuuid {partuuid} [--keychain <service>]")


# ---------------------------------------------------------------- CLI

def main(argv: list[str]) -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--host", required=True, help="fleet host, e.g. vega")
    p.add_argument("--user", help="SSH user (default: from your ssh config)")
    p.add_argument("--ssh", default="ssh", help="ssh client command (default: ssh)")
    p.add_argument("--dry-run", action="store_true",
                   help="read-only: inspect the host and print the commands that would run; no key needed")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("info", help="list disks (read-only)")

    s = sub.add_parser("setup", help="set up a NEW drive (destroys its contents)")
    s.add_argument("--serial", required=True, help="drive serial, from 'info'")
    s.add_argument("--name", required=True, help="drive name, e.g. WDE6T")
    g = s.add_mutually_exclusive_group()
    g.add_argument("--generate", action="store_true", help="generate a 64-hex key onto the clipboard")
    g.add_argument("--keychain", metavar="SERVICE", help="read the key from a macOS Keychain item")
    g.add_argument("--key-env", metavar="VAR", help="read the key from environment variable VAR (or from --env-file)")
    s.add_argument("--env-file", metavar="FILE", help="with --key-env: read VAR from this .env file instead")
    s.add_argument("--like", metavar="REF",
                   help="copy LUKS version/cipher/key size/sector size/PBKDF/hash from an existing "
                        "LUKS partition on the host (PARTUUID or /dev/... path); reads no key")
    s.add_argument("--owner", help="chown the new filesystem's root to this user")
    s.add_argument("--header-backup", metavar="FILE", help="save a LUKS header backup to this local file")
    s.add_argument("--allow-non-usb", action="store_true")
    s.add_argument("--allow-short-key", action="store_true")

    m = sub.add_parser("mount", help="unlock and mount an existing drive")
    m.add_argument("--name", required=True)
    m.add_argument("--partuuid", required=True)
    mg = m.add_mutually_exclusive_group()
    mg.add_argument("--keychain", metavar="SERVICE", help="read the key from a macOS Keychain item")
    mg.add_argument("--key-env", metavar="VAR", help="read the key from environment variable VAR (or from --env-file)")
    m.add_argument("--env-file", metavar="FILE", help="with --key-env: read VAR from this .env file instead")

    u = sub.add_parser("umount", help="unmount and lock a drive")
    u.add_argument("--name", required=True)

    args = p.parse_args(argv)
    if getattr(args, "name", None) and not NAME_RE.match(args.name):
        die("--name may contain only letters, digits, '-' and '_' (max 32)")
    if getattr(args, "partuuid", None) and not UUID_RE.match(args.partuuid):
        die("--partuuid is not a UUID")
    if getattr(args, "env_file", None) and not getattr(args, "key_env", None):
        die("--env-file needs --key-env VAR")
    if getattr(args, "header_backup", None) and os.path.exists(args.header_backup):
        die(f"{args.header_backup} already exists; refusing to overwrite")

    host = Host(f"{args.user}@{args.host}" if args.user else args.host, args.ssh, args.dry_run)
    {"info": cmd_info, "setup": cmd_setup, "mount": cmd_mount, "umount": cmd_umount}[args.cmd](host, args)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except KeyboardInterrupt:
        die("interrupted")
