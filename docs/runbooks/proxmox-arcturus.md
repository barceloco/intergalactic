# Proxmox Host: arcturus

arcturus is a Proxmox VE 9 hypervisor on an HP Elite Mini 800 G9 (i7-12700T,
12 cores / 20 threads, Intel UHD 770 graphics, 16 GB DDR5 now, 48 GB later). It takes
over everything vega and rigel run today, plus immich from the Synology. It
runs VMs only; each VM is a fleet host in its own right and goes through
bootstrap, foundation and production like the Pis.

**Status: built in the repo, not yet run on hardware.** The first run is the
test; the network step rolls itself back if the host does not come back.

## Layout

| VM | Role | From | RAM, 16 GB profile | RAM, 48 GB profile |
|---|---|---|---|---|
| megrez (103) | edge: Traefik, CoreDNS | rigel | 768 MB | 2 GB |
| phecda (106) | Samba file server | vega, rigel | 768 MB | 2 GB |
| dubhe (101) | production apps: aispector, callosal, docgen | vega | 2.5 GB | 10 GB |
| alioth (104) | media: Jellyfin (iGPU), Audiobookshelf, Navidrome | new | 1.5 GB | 6 GB |
| alkaid (105) | immich | mpnas | 4 GB (immich minimum) | 6 GB |
| merak (102) | backups, checks, the LUKS USB drives | new | 768 MB | 2 GB |
| mizar (107) | dev: csa, callosal demo | rigel | off (dev stays on rigel) | 6 GB |
| alcor (108) | isolated sandbox for the OpenClaw agent | vega | off | off until `enabled: true` |
| host | Proxmox + ZFS cache (capped) | | 3 GB (cache 1 GB) | 6 GB (cache 4 GB) |

**One switch selects the profile:** `arcturus_memory_profile` in
`host_vars/arcturus.yml` (`16gb` now). The 16 GB profile is tight but
complete: everything from vega plus immich, with dubhe and alkaid the first
to feel it (immich's machine learning is the largest single user). After
adding memory, set `48gb` and rerun production (it creates mizar), then raise
each running VM's memory (`qm set <vmid> --memory <MB>`, restart the VM):
existing VMs are never resized automatically. The VM role refuses a VM list
that does not fit in the installed memory, and the ZFS cache is capped so it
never squeezes the VMs. Check both profiles any time with
`./scripts/test-arcturus-profiles.sh`.

**Disks:**
- **SATA SSD (500 GB):** Debian 13 + Proxmox, unencrypted. It holds no data
  and no keys, only the OS, the Tailscale node key and a stock Debian VM
  template.
- **2 x 4 TB NVMe:** one encrypted ZFS pool, `tank`, a **stripe** (8 TB, no
  redundancy: if either drive dies the pool is lost and is restored from the
  Synology). It holds every VM disk and all data:

```
tank (encrypted; passphrase never stored)
├── vm/          VM disks (OS, app databases, secrets)
├── vzdump/      nightly backups of every VM
├── documents/   phecda rw, merak ro
├── immich/      alkaid rw, phecda ro, merak ro
├── music/       phecda rw, alioth ro, merak ro
├── audiobooks/  phecda rw, alioth ro, merak ro
└── video/       phecda rw, alioth ro, merak ro
```

VMs see datasets through virtiofs. **Read-only is enforced by arcturus** (a
read-only bind mount), not by the VM: a compromised alioth cannot delete or
encrypt the media.

## Security model

- **Nothing is reachable from the internet.** App domains (`<app>.exnada.com`)
  resolve only inside the tailnet, through CoreDNS on megrez.
- **Allow-list firewall** on the host and in every VM: SSH and ping from the
  tailnet and the LAN, the web UI (8006) from the tailnet only, app ports only
  from megrez, Samba (phecda) from the tailnet and the LAN.
- **No encryption key on the machine**, TPM included. After every boot the
  pool is locked and the VMs are off until the operator unlocks from the Mac.
  `proxmox_storage` refuses a pool whose key could be loaded any other way.
- **The web UI is restricted twice** (firewall and pveproxy), root's password
  is locked, the admin is `armand@pve` with two-factor.
- **The hypervisor runs nothing but VMs.** No Docker, no LXC.
- **Separation by risk:** the GoDaddy key lives only on megrez; the agent
  sandbox (alcor) gets no data and no shares.
- **Snapshots and backups are out of the VMs' reach:** host snapshots
  (sanoid) and nightly VM backups (vzdump) on the encrypted pool; the
  Synology pulls from merak read-only and keeps its own immutable snapshots.
- **Alerts** (ntfy, role `notify`): pool locked after boot, pool and drive
  errors, scrub results, UPS events, stale backups.
- CPU microcode, kernel hardening, rpcbind off, every download verified.

## 1. Prepare the system SSD (on the Mac, no screen needed)

```bash
./scripts/fetch-debian-image.sh            # Debian 13 "generic" image, SHA-512 verified
./scripts/make-cloud-init-seed.sh arcturus # first-boot seed: hostname, armand, your SSH keys
```

Each script prints the exact commands that follow; they erase a disk, so
check the target in `diskutil list` every time:

1. The SATA SSD in a USB-SATA adapter: write the image to it with `dd`.
2. A USB stick: format it as FAT32 named `CIDATA`, copy `user-data` and
   `meta-data` onto it.

**The two NVMe drives are erased later, when the pool is created.** Copy
anything on them elsewhere first.

## 2. First boot

1. SSD into the 2.5" bay (HP's bracket and SATA cable), NVMe drives into the
   two M.2 slots, CIDATA stick and Ethernet plugged in. Power on.
2. Find its address in the router's client list; reserve it there.
3. `ssh armand@<address>` with your key. Remove the stick.

**Once, with a screen** (DisplayPort-to-HDMI cable to a TV), because a
headless HP can stop at a BIOS prompt that looks like a dead box. In the BIOS
(F10):
- enable **VT-x** and **VT-d**, keep **Secure Boot** on
- set a **BIOS administrator password**, boot from the SATA SSD, disable USB
  boot afterwards
- set **power on after AC loss**
- disable **Intel AMT** (remote management)
- update the BIOS to the latest version, with the old RAM still in, before
  adding new memory

## 3. Fill in the settings

- `hosts-bootstrap.yml` and `hosts-foundation.yml`: arcturus's address and
  each VM's address (the `CHANGE_ME_LAN_IP` entries).
- `host_vars/arcturus.yml`: `proxmox_bridge_nic` (`ip -br link`),
  `proxmox_address_cidr` (static, outside DHCP), `proxmox_gateway`,
  `proxmox_keyring_sha256` (from the Proxmox wiki page "Install Proxmox VE on
  Debian 13 Trixie"; never computed from the downloaded file), and each VM's
  `address_cidr`.
- `all_secrets.yml`: `proxmox_admin_password` (12+ characters),
  `notify_ntfy_topic`, `immich_db_password`, `samba_armand_passwords['phecda']`.

## 4. Bootstrap and foundation, then the pool

```bash
./scripts/run-ansible.sh prod arcturus bootstrap
./scripts/run-ansible.sh prod arcturus foundation
./scripts/run-ansible.sh prod arcturus production   # Proxmox; stops before VMs: no pool yet
./scripts/create-encrypted-pool.sh                  # lists the disks
./scripts/create-encrypted-pool.sh <nvme-id-1> <nvme-id-2>
./scripts/run-ansible.sh prod arcturus production   # datasets, storages, shares, VMs
```

`create-encrypted-pool.sh` refuses a disk that is mounted, partitioned or
carries any signature, and never wipes anything itself. It asks for the
passphrase twice: **store it in your password manager and keep an offline
copy elsewhere. Lose it and the data is gone.**

Then, in the web UI (`https://arcturus.tailb821ac.ts.net:8006`, realm
"Proxmox VE authentication server", user `armand`): **enable two-factor**
under Datacenter > Permissions > Two Factor.

## 5. Every reboot: unlock

```bash
./scripts/unlock-arcturus.sh
```

It refuses a host whose SSH key it does not recognise, sends the passphrase
through SSH to the unlock helper, mounts everything, creates the read-only
shares, and starts the VMs in order (megrez first). After a power outage you
get an ntfy alert "Pool locked". Upgrades with a reboot wait for the unlock:

```bash
./scripts/run-ansible.sh prod arcturus upgrade -e os_upgrade_apply=true -e os_upgrade_reboot=true
# ... when it says so: ./scripts/unlock-arcturus.sh (in a second terminal)
```

## 6. The VMs

Each VM joins the fleet like a new Pi: bootstrap, foundation, production
(`./scripts/run-ansible.sh prod <vm> <phase>`). After foundation, add its
Tailscale IPv4 to `fleet_tailscale_ipv4` in `group_vars/all.yml`; megrez must
be there before the app VMs' firewalls (`from: [megrez]`) can render.

- **Docker on the Mac cannot reach the LAN** for a VM's first two phases:
  grant Docker Desktop local network access, or run them from a machine on
  the LAN (see the docker-desktop note in the lessons-learned docs).
- **GitHub deploy keys:** dubhe and mizar generate new per-repo keys; register
  each printed public key as a read-only deploy key.
- **alioth, graphics for Jellyfin:** set `proxmox_gpu_passthrough: true` and
  uncomment alioth's `pci_devices`, rerun production, restart alioth, then
  `jellyfin_hw_accel: true`. Untested on this hardware until the first run.
- **Image versions** (Jellyfin, Audiobookshelf, Navidrome, immich) are
  pinned in host_vars on purpose and empty until set; the roles refuse to run
  without them.
- **merak, backup drives:** plug vega's 6 TB LUKS drives into arcturus, read
  their ids with `lsusb`, put them in merak's `usb_devices`, rerun production,
  restart merak. Unlock them by hand over SSH, as on vega.

Existing VMs are never reconfigured or recreated; only passthrough devices and
shares are added, and a running VM is told (not forced) to restart.

## 7. UPS

With a UPS on USB (CyberPower CP850PFCLCD recommended): set
`proxmox_nut_enabled: true` and rerun production. On low battery the host
shuts down cleanly, VMs first. When power returns, the BIOS powers it on and
you get the "Pool locked" alert.

## 8. Acceptance before migrating anything

None of this is optional (see the restore and failover runbooks):
1. **Power-loss drill:** pull the plug, plug it back, receive the alert,
   unlock, every VM back.
2. **Read-only check:** from alioth and merak, a write to a read-only share
   fails (the `virtiofs_mounts` role also checks it).
3. **Restore drill:** restore a VM and a dataset from the Synology, compare.
4. **Failover drill:** `docs/runbooks/failover-to-pi.md`.
5. **Alerts arrive** on the phone for each class above.

## Not yet proven on hardware

- The Proxmox install itself and the network move onto `vmbr0`.
- virtiofs directory mappings and their exact `pvesh`/`qm` syntax on
  Proxmox VE 9; read-only via the host's bind mounts.
- `zfs load-key` reading the piped passphrase (expected: it reads stdin when
  stdin is not a terminal).
- iGPU passthrough to alioth.

## Image notes

Host and VMs use Debian's **generic** image (netplan + systemd-networkd).
The **genericcloud** variant is avoided: with it, cloud-init on Debian 13 puts
Proxmox's DNS servers on the loopback interface, where they never take effect
(Proxmox forum thread 170804, unfixed as of mid-2026).
