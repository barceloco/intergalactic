# Scripts Directory

This directory contains utility scripts for managing the intergalactic infrastructure deployment.

## Running Scripts on rigel from Your Mac

To run scripts on rigel from your local Mac, use the `run-on-rigel.sh` wrapper:

```bash
# Run any script on rigel
./scripts/run-on-rigel.sh <script-name> [args...]

# Examples:
./scripts/run-on-rigel.sh check-dev-exnada-traefik.sh
./scripts/run-on-rigel.sh create-traefik-dev-config.sh
./scripts/run-on-rigel.sh diagnose-dev-exnada.sh
```

**Configuration:**
- Set `RIGEL_HOST` environment variable to override host (default: `rigel`)
- Set `SSH_KEY` environment variable to override SSH key (default: `~/.ssh/intergalactic_ansible`)
- Set `RIGEL_USER` environment variable to override user (default: `ansible`)

**What it does:**
1. Copies the script to rigel via SCP
2. Makes it executable
3. Runs it via SSH
4. Shows output in real-time

## Core Deployment Scripts

### `run-ansible.sh`

**Purpose**: Main deployment script for three-phase infrastructure deployment

**Usage**:
```bash
./scripts/run-ansible.sh <env> <hostname> <phase>
```

**Phases**:
- `bootstrap` - Phase 1: Initial access setup (creates ansible user, disables password auth)
- `foundation` - Phase 2: Network + security (Tailscale, firewall, Docker, monitoring)
- `production` - Phase 3: Application services (DNS, ingress, deploy user, advanced features)

**Examples**:
```bash
./scripts/run-ansible.sh prod rigel bootstrap
./scripts/run-ansible.sh prod rigel foundation
./scripts/run-ansible.sh prod rigel production
```

**Features**:
- Automatically selects correct inventory file based on phase
- Handles SSH key mounting for Docker container
- Provides phase-specific guidance and next steps
- Validates Tailscale connectivity for production phase
- Supports Ansible tags and other options for faster iteration

**Faster Iteration with Tags**:
```bash
# Run only validation/health-check tasks (skip deployment)
./scripts/run-ansible.sh prod rigel production --tags validation,health-check

# Skip validation tasks (deploy only)
./scripts/run-ansible.sh prod rigel production --skip-tags validation

# Run only edge_ingress role
./scripts/run-ansible.sh prod rigel production --tags edge_ingress

# Start at a specific task (useful when debugging)
./scripts/run-ansible.sh prod rigel production --start-at-task "Deploy Traefik systemd service"

# Run only tasks that changed (idempotency check)
./scripts/run-ansible.sh prod rigel production --check --diff
```

**Available Tags**:
- `validation` - All validation tasks (health checks, connectivity tests)
- `health-check` - Health check tasks only
- `production` - All production phase tasks
- `services` - Service deployment tasks
- `monitoring` - Monitoring-related tasks
- `security` - Security-related tasks
- Role-specific tags: `edge_ingress`, `internal_dns`, `docker_deploy`, etc.

## Validation and Verification Scripts

### `validate-playbooks.sh`

**Purpose**: Validates all Ansible playbooks for syntax errors

**Usage**:
```bash
./scripts/validate-playbooks.sh
```

**What it does**:
- Runs `ansible-playbook --syntax-check` on all playbooks
- Checks for common YAML syntax issues
- Reports errors and warnings

**When to use**:
- Before committing changes
- After modifying playbooks
- As part of CI/CD pipeline

### `verify-inventory-users.sh`

**Purpose**: Verifies that inventory files use correct users for each phase

**Usage**:
```bash
./scripts/verify-inventory-users.sh
```

**What it checks**:
- Bootstrap inventory: All hosts use `ansible_user: armand`
- Production inventory: All hosts use `ansible_user: ansible`
- All hosts are present in both inventories

**When to use**:
- After adding new hosts
- When troubleshooting authentication issues
- Before running playbooks

## Testing Scripts

### `run-linting.sh`

**Purpose**: Run linting checks on Ansible codebase (containerized)

**Usage**:
```bash
./scripts/run-linting.sh [ansible-lint|yamllint|all]
```

**What it does**:
- Builds testing container automatically (if needed)
- Runs `ansible-lint` on all Ansible files
- Runs `yamllint` on all YAML files
- Reports errors and warnings

**When to use**:
- Before committing changes
- After modifying Ansible files
- As part of CI/CD pipeline
- To catch code quality issues early

**Requirements**:
- **Only Docker** (no Python, pip, or other tools needed)
- Docker must be running

### `run-molecule-tests.sh`

**Purpose**: Run Molecule tests for all roles (containerized)

**Usage**:
```bash
./scripts/run-molecule-tests.sh [role-name|all]
```

**What it does**:
- Builds testing container automatically (if needed)
- Runs Molecule tests for roles with test infrastructure
- Tests role idempotency and convergence
- Verifies role configuration
- Reports test results

**Available roles**:
- `docker_deploy` - Docker deployment user setup
- `internal_dns` - CoreDNS configuration
- `edge_ingress` - Traefik ingress routing
- `firewall_nftables` - Firewall configuration

**When to use**:
- After modifying role code
- Before merging role changes
- To verify role functionality
- As part of CI/CD pipeline

**Requirements**:
- **Only Docker** (no Python, pip, or other tools needed)
- Docker must be running
- Docker socket must be accessible (for Docker-in-Docker)

### `run-all-tests.sh`

**Purpose**: Run all automated tests (containerized)

**Usage**:
```bash
./scripts/run-all-tests.sh [--skip-lint] [--skip-molecule] [--skip-testinfra]
```

**What it does**:
- Builds testing container automatically (if needed)
- Runs linting checks (`run-linting.sh`)
- Validates playbook syntax (`validate-playbooks.sh`)
- Runs Molecule tests (`run-molecule-tests.sh`)
- Provides summary of all test results

**When to use**:
- Before committing major changes
- Before merging pull requests
- As part of CI/CD pipeline
- To verify overall code quality

**Options**:
- `--skip-lint` - Skip linting phase
- `--skip-molecule` - Skip Molecule tests
- `--skip-testinfra` - Skip Testinfra tests (always skipped in automated run)

**Requirements**:
- **Only Docker** (no Python, pip, or other tools needed)
- Docker must be running
- Docker socket accessible for Molecule tests

## Diagnostic Scripts

### `dns-tools.sh` ⭐ NEW

**Purpose**: Unified DNS diagnostic and testing tool (consolidates 6 DNS-related scripts)

**Usage**:
```bash
./scripts/dns-tools.sh <command> [options]
```

**Commands**:
- `check-nameservers` - Check DNS nameserver configuration
- `test-coredns` - Test CoreDNS functionality
- `validate-split-dns` - Validate split-horizon DNS setup
- `test-resolution <hostname>` - Test DNS resolution for specific host
- `check-acme-records` - Check ACME DNS records

**Examples**:
```bash
# Check DNS configuration
./scripts/dns-tools.sh check-nameservers

# Test CoreDNS
./scripts/dns-tools.sh test-coredns

# Validate split-horizon DNS
./scripts/dns-tools.sh validate-split-dns

# Test specific host resolution
./scripts/dns-tools.sh test-resolution mpnas.exnada.com

# Get help
./scripts/dns-tools.sh --help
```

**Features**:
- Unified command interface with subcommands
- Color-coded output (info, success, warning, error)
- Built-in help documentation
- Consistent error handling

**When to use**:
- After deploying `internal_dns` role
- When troubleshooting DNS resolution issues
- To verify CoreDNS configuration
- For split-horizon DNS validation

### `traefik-tools.sh` ⭐ NEW

**Purpose**: Unified Traefik diagnostic and testing tool (consolidates 3 Traefik-related scripts)

**Usage**:
```bash
./scripts/traefik-tools.sh <command> [options]
```

**Commands**:
- `status` - Check Traefik container status
- `check-routing` - Check routing configuration
- `test-backend <hostname>` - Test backend connectivity for a route
- `diagnose` - Full diagnostic of Traefik setup
- `logs [-f]` - Show Traefik logs (with optional follow)
- `test-route <url>` - Test specific route end-to-end

**Examples**:
```bash
# Check Traefik status
./scripts/traefik-tools.sh status

# Check routing configuration
./scripts/traefik-tools.sh check-routing

# Run full diagnostic
./scripts/traefik-tools.sh diagnose

# Test specific route
./scripts/traefik-tools.sh test-route https://mpnas.exnada.com

# View logs
./scripts/traefik-tools.sh logs -f

# Get help
./scripts/traefik-tools.sh --help
```

**Features**:
- Unified command interface with subcommands
- Comprehensive diagnostics in one place
- Port binding verification
- Configuration file validation
- Log analysis
- End-to-end route testing

**When to use**:
- After deploying `edge_ingress` role
- When troubleshooting routing issues
- To verify Traefik configuration
- For SSL/TLS certificate issues
- For backend connectivity problems

### `verify-reverse-proxy.sh`

**Purpose**: Verifies CoreDNS and Traefik deployment status

**Usage**:
```bash
./scripts/verify-reverse-proxy.sh <hostname>
```

**What it checks**:
- Container status (CoreDNS, Traefik)
- Container logs for errors
- DNS resolution for private hosts
- Firewall rules for DNS/HTTP/HTTPS ports

**When to use**:
- After deploying `internal_dns` or `edge_ingress` roles
- When troubleshooting DNS or ingress issues
- To verify services are running correctly

### `diagnose-reverse-proxy.sh`

**Purpose**: Diagnoses issues with CoreDNS and Traefik deployment

**Usage**:
```bash
./scripts/diagnose-reverse-proxy.sh <hostname>
```

**What it checks**:
- If roles are enabled in inventory
- If docker-compose files exist
- If data directories exist
- If containers exist
- Port conflicts
- Docker service status

**When to use**:
- When `verify-reverse-proxy.sh` shows issues
- When services fail to start
- For detailed troubleshooting

### `check-role-execution.sh`

**Purpose**: Checks if specific Ansible roles executed in the last playbook run

**Usage**:
```bash
./scripts/check-role-execution.sh <role-name>
```

**What it does**:
- Parses Ansible playbook output
- Identifies which roles ran
- Helps diagnose why roles might have been skipped

**When to use**:
- When a role didn't run as expected
- To verify role execution
- When troubleshooting conditional role execution

## Migration and Reconfiguration Scripts

### `migrate-to-three-phase.sh`

**Purpose**: Helper script for migrating existing hosts to three-phase structure

**Usage**:
```bash
./scripts/migrate-to-three-phase.sh <hostname> [tailscale-hostname]
```

**What it does**:
- Checks host accessibility
- Verifies Tailscale is installed and connected
- Detects Tailscale hostname automatically
- Tests Tailscale connectivity
- Provides instructions for updating inventory

**When to use**:
- When re-configuring existing hosts
- When migrating from old single-phase structure
- To get Tailscale hostname for inventory update

## Service Management Scripts

### `update-samba.sh`

**Purpose**: Updates Samba configuration without running full playbook

**Usage**:
```bash
./scripts/update-samba.sh prod <hostname>
```

**What it does**:
- Deploys updated Samba configuration from template
- Validates configuration syntax
- Restarts Samba services (smbd, nmbd)

**When to use**:
- After modifying Samba template
- After changing Samba variables
- For quick Samba configuration refresh
- When troubleshooting Samba issues

**Requirements**:
- Host must be accessible via Tailscale
- Host must have Samba installed
- Host must have `enable_samba: true` in host_vars

## System Setup Scripts

### `setup-partitions.sh`

**Purpose**: Interactive helper script for partitioning 128GB drives

**Usage**:
```bash
./scripts/setup-partitions.sh
```

**What it does**:
- Guides through partitioning process using `parted`
- Creates boot (1GB), root (32GB), and data partitions
- Formats partitions appropriately

**When to use**:
- When setting up new Raspberry Pi with 128GB drive
- When repartitioning existing drives
- Before first deployment

**Warning**: This will destroy all data on the drive!

### `encrypt-home-partition.sh`

**Purpose**: Helper script for encrypting external devices using LUKS

**Usage**:
```bash
./scripts/encrypt-home-partition.sh <device> <base64-passphrase>
```

**What it does**:
- Encrypts external USB drives or network storage devices
- Uses LUKS encryption
- Formats encrypted device

**When to use**:
- When setting up encrypted external storage
- For USB drives or network storage
- **Note**: Internal partitions are NOT encrypted - this is only for external devices

**Warning**: This will destroy all data on the device!

### `provision_sd.py`

**Purpose**: Headless SD card provisioning for Debian-based Raspberry Pi images

**Usage**:
```bash
sudo python3 scripts/provision_sd.py <image-file> <device> --hostname <hostname>
```

**What it does**:
- Writes image to target block device
- Mounts partitions
- Sets hostname
- Injects SSH authorized_keys for automation user
- Writes sshd drop-in to disable password auth

**When to use**:
- When provisioning new Raspberry Pi SD cards
- For automated initial setup
- Before first boot

**Requirements**:
- Must run as root (sudo)
- Requires PyYAML: `pip install pyyaml`

## Script Categories

### Essential Scripts
- `run-ansible.sh` - Core deployment (always needed)
- `validate-playbooks.sh` - Quality assurance (recommended)
- `verify-inventory-users.sh` - Inventory validation (recommended)

### Testing Scripts
- `run-linting.sh` - Code quality checks (recommended)
- `run-molecule-tests.sh` - Role testing (for role development)
- `run-all-tests.sh` - Comprehensive test suite (for CI/CD)

### Diagnostic Scripts
- `dns-tools.sh` ⭐ **NEW** - Unified DNS diagnostics (consolidates 6 scripts)
- `traefik-tools.sh` ⭐ **NEW** - Unified Traefik diagnostics (consolidates 3 scripts)
- `verify-reverse-proxy.sh` - Service verification
- `diagnose-reverse-proxy.sh` - Detailed troubleshooting
- `check-role-execution.sh` - Role execution verification

### Utility Scripts
- `migrate-to-three-phase.sh` - Host migration helper
- `update-samba.sh` - Samba configuration update
- `setup-partitions.sh` - Drive partitioning helper
- `encrypt-home-partition.sh` - External device encryption
- `provision_sd.py` - SD card provisioning

## Script Requirements

### Deployment Scripts
- Docker (for Ansible runner)
- SSH keys configured
- Access to target hosts
- Appropriate inventory files

### Testing Scripts
- **Only Docker** (no Python, pip, or other tools needed!)
- Docker must be running
- For Molecule: Docker socket accessible

**Key Benefit**: Testing scripts are fully containerized - no host installation required!

## Getting Help

For script-specific help:
```bash
./scripts/<script-name> --help
# or
./scripts/<script-name>  # (many show usage on error)
```

For general deployment help, see the main [README.md](../README.md).
