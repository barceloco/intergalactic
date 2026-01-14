# luks Role

Installs cryptsetup for mounting external LUKS-encrypted devices.

## What This Role Does

- Installs cryptsetup package
- Enables mounting of LUKS-encrypted USB drives
- Enables mounting of LUKS-encrypted network storage

## Requirements

- Debian distribution
- Ansible 2.9+
- Root/sudo access

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_luks` | `true` | Enable cryptsetup installation |

## Dependencies

- Part of Phase 3 (Production)
- Independent role

## Phase

**Phase 3: Production** - Security tooling

## Important Note

**Internal partitions are NOT encrypted**. This role only installs tools for mounting **external** encrypted devices (USB drives, network storage).

## Mount Encrypted Device

```bash
# Open encrypted device
sudo cryptsetup open /dev/sdX1 my-encrypted-drive

# Mount the decrypted device
sudo mount /dev/mapper/my-encrypted-drive /mnt

# When done
sudo umount /mnt
sudo cryptsetup close my-encrypted-drive
```

## License

Proprietary - All Rights Reserved, ExNada Inc.
