# common_bootstrap Role

Critical bootstrap role that establishes secure automation access by creating the `ansible` user, disabling password authentication, and setting up SSH keys. This role must run first on any new host.

## What This Role Does

- Creates the `ansible` automation user
- Disables password-based SSH authentication (public key only)
- Sets up SSH keys for automation and human users
- Configures SSH to use consolidated key location (`/etc/ssh/authorized_keys.d/%u`)
- Sets up passwordless sudo for `ansible` user
- Sets hostname (if configured)
- **CRITICAL**: Prevents lockout by ensuring keys are in place before disabling password auth

## Requirements

- Debian distribution (tested on Debian trixie/testing)
- Ansible 2.9+
- Root/sudo access (role uses `become: true`)
- Initial user must have sudo access (typically `armand` or `pi`)
- SSH keys must be configured in `all_secrets.yml`

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `automation_user` | `ansible` | Name of the automation user to create |
| `automation_authorized_keys` | (required) | List of SSH public keys for automation user (from `all_secrets.yml`) |
| `human_users` | (required) | List of human user accounts with SSH keys (from `all_secrets.yml`) |
| `hostname` | (optional) | Hostname to set (if configured in host_vars) |

## Dependencies

None (this is the first role that runs).

## Critical Bootstrap Sequence

The role follows a specific sequence to prevent lockout:

1. **Configure SSH** (but don't restart yet):
   - Set `AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u`
   - Disable password authentication in config

2. **Copy existing human user keys**:
   - Copy keys from `~/.ssh/authorized_keys` (if present)
   - Copy keys from `all_secrets.yml`
   - Place in `/etc/ssh/authorized_keys.d/{username}`

3. **Create ansible user**:
   - Create user account
   - Copy automation SSH keys to `/etc/ssh/authorized_keys.d/ansible`
   - Set up passwordless sudo

4. **Restart SSH**:
   - Now safe to restart - all keys are in place
   - Password authentication is disabled

## Usage Examples

### Basic Usage

The role is automatically used in bootstrap playbooks:

```yaml
# In playbooks/{hostname}-bootstrap.yml
roles:
  - common_bootstrap
```

### With Hostname

```yaml
# In host_vars/rigel.yml
hostname: rigel
```

The role will set the hostname during bootstrap.

## Secrets Configuration

SSH keys must be configured in `all_secrets.yml`:

```yaml
# Automation user keys
automation_authorized_keys:
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... ansible@control"

# Human user keys
human_users:
  - name: armand
    authorized_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... armand@laptop"
```

## What Gets Created

1. **SSH Configuration**: `/etc/ssh/sshd_config.d/10-intergalactic-bootstrap.conf`
   - `AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u`
   - `PasswordAuthentication no`
   - `PubkeyAuthentication yes`

2. **SSH Keys Directory**: `/etc/ssh/authorized_keys.d/`
   - Contains SSH keys for all users
   - Permissions: 755 (directory), 644 (key files)

3. **Automation User**: `ansible` user with:
   - Home directory: `/home/ansible`
   - Shell: `/bin/bash`
   - Groups: `sudo`
   - SSH keys in `/etc/ssh/authorized_keys.d/ansible`

4. **Sudo Configuration**: `/etc/sudoers.d/90-ansible`
   - Passwordless sudo for `ansible` user
   - No TTY required (for automation)

5. **Hostname** (if configured):
   - Sets system hostname
   - Updates `/etc/hostname`

## Security Considerations

- **Password Authentication Disabled**: SSH only accepts public key authentication
- **Consolidated Key Location**: All SSH keys in `/etc/ssh/authorized_keys.d/` (supports encrypted home directories)
- **Lockout Prevention**: Keys are placed before password auth is disabled
- **Sudo Access**: Automation user has passwordless sudo (treat as privileged)

## Troubleshooting

### Locked Out After Bootstrap

If you're locked out, you may need physical access or console access:

1. **Check SSH keys are in place**:
   ```bash
   sudo cat /etc/ssh/authorized_keys.d/ansible
   sudo cat /etc/ssh/authorized_keys.d/armand
   ```

2. **Check SSH configuration**:
   ```bash
   sudo grep -E "(PasswordAuthentication|AuthorizedKeysFile)" /etc/ssh/sshd_config.d/*
   ```

3. **Check SSH service**:
   ```bash
   sudo systemctl status ssh
   ```

4. **If keys are missing**, add them manually:
   ```bash
   sudo mkdir -p /etc/ssh/authorized_keys.d
   echo "your-public-key" | sudo tee /etc/ssh/authorized_keys.d/ansible
   sudo chmod 644 /etc/ssh/authorized_keys.d/ansible
   sudo systemctl reload ssh
   ```

### Ansible User Cannot Sudo

1. **Check sudoers file**:
   ```bash
   sudo cat /etc/sudoers.d/90-ansible
   ```

2. **Test sudo access**:
   ```bash
   sudo -u ansible sudo whoami
   ```

3. **Verify user is in sudo group**:
   ```bash
   groups ansible
   ```

### SSH Keys Not Working

1. **Check key file permissions**:
   ```bash
   ls -la /etc/ssh/authorized_keys.d/
   ```

2. **Check SSH configuration**:
   ```bash
   sudo sshd -T | grep authorizedkeysfile
   ```

3. **Check SSH logs**:
   ```bash
   sudo journalctl -u ssh -n 50
   ```

### Hostname Not Set

1. **Check hostname variable**:
   - Verify `hostname` is set in `host_vars/{hostname}.yml`

2. **Check current hostname**:
   ```bash
   hostname
   cat /etc/hostname
   ```

3. **Set manually if needed**:
   ```bash
   sudo hostnamectl set-hostname rigel
   ```

## Bootstrap Process Flow

```
1. Install OpenSSH server
   ↓
2. Create /etc/ssh/authorized_keys.d directory
   ↓
3. Configure SSH (AuthorizedKeysFile, disable password auth)
   ↓
4. Ensure human users exist
   ↓
5. Copy human user keys to /etc/ssh/authorized_keys.d/{username}
   ↓
6. Create ansible user
   ↓
7. Copy automation keys to /etc/ssh/authorized_keys.d/ansible
   ↓
8. Configure passwordless sudo for ansible
   ↓
9. Set hostname (if configured)
   ↓
10. Restart SSH service (now safe - all keys in place)
```

## Notes

- The role is idempotent: running it multiple times produces no changes
- **CRITICAL**: This role disables password authentication - ensure SSH keys are configured correctly
- SSH keys are copied from both existing `~/.ssh/authorized_keys` and `all_secrets.yml`
- The role validates that automation keys are configured before proceeding
- Hostname is only set if `hostname` variable is defined
- The role prevents lockout by placing all keys before restarting SSH

## Integration with Other Roles

- **None**: This is the first role that runs (in bootstrap phase)
- **All other roles**: Depend on this role creating the `ansible` user

## Security Best Practices

1. **Use strong SSH keys**: ED25519 or RSA 4096-bit
2. **Protect private keys**: Never commit private keys to repository
3. **Rotate keys regularly**: Update keys in `all_secrets.yml` and re-run bootstrap
4. **Monitor access**: Review SSH logs regularly
5. **Limit sudo access**: The `ansible` user has full sudo - treat as privileged

## License

MIT
