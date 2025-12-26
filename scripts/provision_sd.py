#!/usr/bin/env python3

# Headless SD provisioning for Debian-based Raspberry Pi images.

# - Writes an image to a target block device
# - Mounts partitions
# - Sets hostname
# - Injects SSH authorized_keys for the automation user (default: ansible)
# - Writes sshd drop-in to disable password auth + root SSH

import argparse
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import yaml  # type: ignore
except Exception:
    print("Missing dependency: pyyaml. Install with: python3 -m pip install pyyaml", file=sys.stderr)
    sys.exit(2)


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def require_root() -> None:
    if os.geteuid() != 0:
        print("This script must be run as root (needs to write block devices and mount).", file=sys.stderr)
        sys.exit(1)


def is_block_device(path: str) -> bool:
    p = Path(path)
    return p.exists() and stat.S_ISBLK(p.stat().st_mode)


def guess_partitions(dev: str) -> tuple[str, str]:
    if dev.endswith(tuple("0123456789")):
        return f"{dev}p1", f"{dev}p2"
    return f"{dev}1", f"{dev}2"


def dd_image(image: str, dev: str) -> None:
    print(f"[+] Flashing image to {dev} (THIS ERASES THE DEVICE)")
    run(["dd", f"if={image}", f"of={dev}", "bs=8M", "status=progress", "conv=fsync"])
    run(["sync"])
    run(["partprobe", dev], check=False)


def mount_partition(part: str, mountpoint: str) -> bool:
    try:
        run(["mount", part, mountpoint])
        return True
    except subprocess.CalledProcessError:
        return False


def write_file(path: Path, content: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    if mode is not None:
        os.chmod(path, mode)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="bootstrap/hosts.yaml", help="Path to bootstrap manifest")
    parser.add_argument("--host", required=True, help="Host key in manifest (e.g. rigel)")
    parser.add_argument("--yes", action="store_true", help="Skip confirmation prompt")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    cfg_path = repo_root / args.config
    if not cfg_path.exists():
        print(f"Config not found: {cfg_path}", file=sys.stderr)
        sys.exit(2)

    data = yaml.safe_load(cfg_path.read_text(encoding="utf-8"))
    defaults = data.get("defaults", {})
    hosts = data.get("hosts", {})
    if args.host not in hosts:
        print(f"Host not found in manifest: {args.host}", file=sys.stderr)
        sys.exit(2)

    host_cfg = {**defaults, **hosts[args.host]}
    hostname = args.host
    automation_user = host_cfg["admin_user"]
    keys = host_cfg.get("ssh_authorized_keys", [])
    image = str(repo_root / host_cfg["image"])
    dev = host_cfg["target_device"]

    if not Path(image).exists():
        print(f"Image not found: {image}", file=sys.stderr)
        sys.exit(2)

    require_root()
    if not is_block_device(dev):
        print(f"Not a block device: {dev}", file=sys.stderr)
        sys.exit(2)

    print("=== Provision Plan ===")
    print(f"Host:      {hostname}")
    print(f"Image:     {image}")
    print(f"Device:    {dev}")
    print(f"User:      {automation_user} (automation)")
    print(f"Keys:      {len(keys)} key(s)")
    if not args.yes:
        ans = input("Type 'ERASE' to continue: ").strip()
        if ans != "ERASE":
            print("Aborted.")
            sys.exit(0)

    dd_image(image, dev)

    boot_part, root_part = guess_partitions(dev)

    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        boot_mnt = td_path / "boot"
        root_mnt = td_path / "root"
        boot_mnt.mkdir()
        root_mnt.mkdir()

        print(f"[+] Mounting root partition {root_part}")
        if not mount_partition(root_part, str(root_mnt)):
            print(f"Failed to mount root partition: {root_part}", file=sys.stderr)
            sys.exit(2)

        boot_mounted = False
        if mount_partition(boot_part, str(boot_mnt)):
            boot_mounted = True
            print(f"[+] Mounted boot partition {boot_part}")
        else:
            print("[i] Boot partition not mounted (ok for some images).")

        try:
            write_file(root_mnt / "etc/hostname", hostname + "\n")
            hosts_file = root_mnt / "etc/hosts"
            if hosts_file.exists():
                txt = hosts_file.read_text(encoding="utf-8").splitlines()
            else:
                txt = ["127.0.0.1 localhost"]
            found = False
            for i, line in enumerate(txt):
                if line.startswith("127.0.1.1"):
                    txt[i] = f"127.0.1.1 {hostname}"
                    found = True
                    break
            if not found:
                txt.append(f"127.0.1.1 {hostname}")
            write_file(hosts_file, "\n".join(txt) + "\n")

            ak = root_mnt / "home" / automation_user / ".ssh" / "authorized_keys"
            write_file(ak, "\n".join(keys).strip() + "\n", mode=0o600)
            os.chmod(ak.parent, 0o700)

            sshd_dropin = root_mnt / "etc" / "ssh" / "sshd_config.d" / "10-intergalactic.conf"
            write_file(
                sshd_dropin,
                "PasswordAuthentication no\n"
                "KbdInteractiveAuthentication no\n"
                "PermitRootLogin no\n"
                "PubkeyAuthentication yes\n",
                mode=0o600,
            )

            if boot_mounted:
                try:
                    (boot_mnt / "ssh").touch()
                except Exception:
                    pass

            print("[+] Injection complete.")
        finally:
            run(["sync"], check=False)
            if boot_mounted:
                run(["umount", str(boot_mnt)], check=False)
            run(["umount", str(root_mnt)], check=False)

    print("[+] Done. Boot the Pi, then run Ansible bootstrap.")
