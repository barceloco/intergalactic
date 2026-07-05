# tailscale Role

Installs and configures Tailscale mesh VPN for secure network connectivity.

## What This Role Does

- Installs Tailscale from official repository
- Authenticates with Tailscale using auth key
- Configures Tailscale service to start on boot
- Optionally advertises exit node
- Optionally advertises routes
- Enables network transition from local IP to Tailscale network

## Requirements

- Debian distribution
- Ansible 2.9+
- Root/sudo access
- `tailscale_authkey` configured in `all_secrets.yml`
- Firewall allows UDP port 41641 (initial connection)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_tailscale` | `true` | Enable Tailscale |
| `tailscale_authkey` | (required) | Tailscale authentication key (from all_secrets.yml) |
| `tailscale_advertise_exit_node` | `false` | Advertise as exit node |
| `tailscale_advertise_routes` | `[]` | List of routes to advertise |
| `tailscale_tags` | `[]` | ACL tags to advertise (e.g. `['tag:server']`). Tagged devices never have key expiry, so this makes newly provisioned nodes expiry-proof. Requires the tag + tagOwners in the Tailscale ACL. Applied only on first connect. |

## Dependencies

- Firewall should allow UDP port 41641
- Part of Phase 2 (Foundation)

## Phase

**Phase 2: Foundation** - Network connectivity

## What Gets Installed

- Tailscale package from https://tailscale.com/kb/1174/install-debian
- Tailscale service enabled and started
- Host joined to Tailnet

## Get Tailscale Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Click "Generate auth key"
3. Set Reusable: Yes (for multiple hosts)
4. Set Ephemeral: No (for persistent devices)
5. Copy key to `all_secrets.yml`

## After Foundation Phase

The Tailscale hostname will be displayed. Update `hosts-production.yml` with this hostname for Phase 3.

## Usage Example

```yaml
# In group_vars/all_secrets.yml
tailscale_authkey: "tskey-auth-xxxxxxxxxxxxx"

# In group_vars/all.yml
enable_tailscale: true
tailscale_advertise_exit_node: false
tailscale_advertise_routes: []
```

## License

Proprietary - All Rights Reserved, ExNada Inc.
