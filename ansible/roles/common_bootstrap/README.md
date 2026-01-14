# common_bootstrap Role

Creates the automation user and performs initial system bootstrapping during Phase 1 deployment.

## What This Role Does

- Creates `ansible` automation user with SSH key access
- **Immediately disables password authentication** for SSH (security hardening)
- Adds SSH keys for automation and human users
- Sets up passwordless sudo for automation user
- Installs essential packages (sudo, python3, etc.)
- Configures hostname (if specified)

## Requirements

- Debian distribution
- Ansible 2.9+
- Root/sudo access
- SSH key access for initial user
- `automation_authorized_keys` and `human_users` configured in `all_secrets.yml`

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `automation_user` | `ansible` | Name of the automation user to create |
| `automation_authorized_keys` | (required) | SSH public keys for automation user |
| `human_users` | (required) | List of human users with SSH keys |

## Phase

**Phase 1: Bootstrap** - Creates automation access

## Security Impact

**CRITICAL**: This role **immediately disables password authentication**. Ensure SSH keys are configured before running.

## License

Proprietary - All Rights Reserved, ExNada Inc.
