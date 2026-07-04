# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Intergalactic** is a Raspberry Pi fleet management system for Debian Stable (Trixie) using Ansible. It manages a fleet of Raspberry Pi devices (Gen1-Gen5) through a three-phase deployment model that separates bootstrap, foundation, and production concerns.

**Key Technology Stack:**
- **Deployment**: Ansible (containerized via Docker)
- **Networking**: Tailscale (mesh VPN)
- **DNS**: CoreDNS (internal DNS with failthrough)
- **Reverse Proxy**: Traefik (edge ingress with automatic HTTPS via ACME)
- **Container Runtime**: Docker Engine
- **Testing**: ansible-lint, yamllint, molecule, testinfra (all containerized)

## Three-Phase Deployment Model

This is the core architectural pattern. Understanding it is critical:

### Phase 1: Bootstrap (Local IP → Creates Automation User)
- **Purpose**: Establish secure automation access
- **Connection**: Local IP (192.168.1.x)
- **User**: Initial user (e.g., `armand`)
- **Inventory**: `hosts-bootstrap.yml`
- **Playbook Pattern**: `<hostname>-bootstrap.yml`
- **Command**: `./scripts/run-ansible.sh prod <hostname> bootstrap`
- **What it does**:
  - Creates `ansible` automation user
  - **Immediately disables password authentication** (SSH keys only)
  - Sets up SSH keys for automation and human users
  - Minimal, fast, idempotent

### Phase 2: Foundation (Local IP → Installs Tailscale)
- **Purpose**: Network connectivity and security foundation
- **Connection**: Local IP (may require local network)
- **User**: `ansible` (automation user created in Phase 1)
- **Inventory**: `hosts-foundation.yml`
- **Playbook Pattern**: `<hostname>-foundation.yml`
- **Command**: `./scripts/run-ansible.sh prod <hostname> foundation`
- **Roles**: `common`, `ssh_hardening`, `firewall_nftables`, `fail2ban`, `updates`, `tailscale`, `docker_host`, `monitoring_base`
- **Critical Output**: Tailscale hostname (needed for Phase 3)

### Phase 3: Production (Tailscale Only → Deploys Services)
- **Purpose**: Application services and advanced features
- **Connection**: **Tailscale network ONLY** (rigel.tailb821ac.ts.net)
- **User**: `ansible`
- **Inventory**: `hosts-production.yml` (uses Tailscale hostnames)
- **Playbook Pattern**: `<hostname>-production.yml`
- **Command**: `./scripts/run-ansible.sh prod <hostname> production`
- **Roles**: `docker_deploy`, `internal_dns`, `edge_ingress`, `monitoring_docker`, `luks`
- **Requirement**: MUST connect via Tailscale (playbook enforces this)

**Why Three Phases?**
1. **Network Transition**: Clean transition from local network → Tailscale
2. **Security**: Bootstrap disables password auth immediately, foundation hardens further
3. **Dependencies**: Foundation sets up infrastructure needed by production services

## Commands

### Deployment Commands

```bash
# Phase 1: Bootstrap (create automation user, disable password auth)
./scripts/run-ansible.sh prod <hostname> bootstrap

# Phase 2: Foundation (network + security + Tailscale)
./scripts/run-ansible.sh prod <hostname> foundation

# Phase 3: Production (application services via Tailscale)
./scripts/run-ansible.sh prod <hostname> production

# Migrate existing host to three-phase structure
./scripts/migrate-to-three-phase.sh <hostname> [tailscale-hostname]
```

### Testing Commands (All Containerized - No Local Installation Required)

```bash
# Run all linting checks (ansible-lint, yamllint)
./scripts/run-linting.sh

# Validate playbook syntax
./scripts/validate-playbooks.sh

# Run Molecule tests for roles
./scripts/run-molecule-tests.sh [role-name]

# Run all automated tests
./scripts/run-all-tests.sh [--skip-lint] [--skip-molecule]

# Verify inventory users are correct
./scripts/verify-inventory-users.sh
```

### Diagnostic Commands

```bash
# Verify DNS and Traefik deployment
./scripts/verify-reverse-proxy.sh <hostname>

# Diagnose reverse proxy issues
./scripts/diagnose-reverse-proxy.sh <hostname>

# Check if a role executed in last playbook run
./scripts/check-role-execution.sh <role-name>
```

### Service-Specific Commands

```bash
# Update Samba configuration without full playbook run
./scripts/update-samba.sh prod <hostname>
```

## Architecture

### Directory Structure

```
ansible/
├── inventories/prod/
│   ├── hosts-bootstrap.yml          # Phase 1: Local IP, initial user
│   ├── hosts-foundation.yml         # Phase 2: Local IP, ansible user
│   ├── hosts-production.yml         # Phase 3: Tailscale hostnames, ansible user
│   ├── group_vars/
│   │   ├── all.yml                  # Global settings
│   │   └── all_secrets.yml          # SSH keys, Tailscale auth key (gitignored)
│   └── host_vars/
│       └── <hostname>.yml           # Per-host configuration
├── playbooks/
│   ├── <hostname>-bootstrap.yml     # Phase 1 playbook
│   ├── <hostname>-foundation.yml    # Phase 2 playbook
│   ├── <hostname>-production.yml    # Phase 3 playbook
│   └── shared/                      # Shared tasks (host key verification, etc.)
└── roles/
    ├── common_bootstrap/            # Phase 1: Automation user setup
    ├── common/                      # Phase 2: Base system configuration
    ├── ssh_hardening/               # Phase 2: SSH security
    ├── firewall_nftables/           # Phase 2: Firewall (nftables)
    ├── fail2ban/                    # Phase 2: Intrusion prevention
    ├── tailscale/                   # Phase 2: Mesh VPN
    ├── docker_host/                 # Phase 2: Docker engine
    ├── docker_deploy/               # Phase 3: Deploy user + directory structure
    ├── internal_dns/                # Phase 3: CoreDNS
    ├── edge_ingress/                # Phase 3: Traefik reverse proxy
    ├── monitoring_docker/           # Phase 3: Docker monitoring tools
    └── luks/                        # Phase 3: LUKS for external encrypted devices

scripts/
├── run-ansible.sh                   # Main deployment wrapper
├── run-linting.sh                   # Containerized linting
├── run-molecule-tests.sh            # Containerized role tests
├── validate-playbooks.sh            # Containerized syntax validation
└── [30+ utility scripts]            # See scripts/README.md
```

### Role Execution Order (Production Phase)

**Critical**: Roles must execute in specific order due to dependencies:

1. **docker_deploy** (if enabled) - Creates deploy user, sets up `/home/deploy/docker`, `/home/deploy/srv`, `/home/deploy/logs`
2. **internal_dns** (if enabled) - Deploys CoreDNS for split-horizon DNS
3. **edge_ingress** (if enabled) - Deploys Traefik with built-in ACME for HTTPS
4. **monitoring_docker** - Monitoring tools (ctop, lazydocker, etc.)
5. **luks** - Installs cryptsetup for external encrypted devices

**Why this order?**
- `docker_deploy` must run first because it configures Docker data-root (`/home/deploy/docker`)
- `internal_dns` must run before `edge_ingress` for DNS resolution during certificate validation
- `edge_ingress` uses Traefik's built-in ACME resolver (no separate cert_issuer role needed)

### Key Architectural Concepts

#### Split-Horizon DNS (CoreDNS)
- **Purpose**: Resolve internal hosts to Tailscale IPs, forward external domains upstream
- **Implementation**: CoreDNS with `template` plugin for private hosts + `forward` plugin for external
- **Example**:
  - `mpnas.exnada.com` → `100.120.170.43` (Tailscale IP)
  - `www.exnada.com` → Forward to `8.8.8.8` (public DNS)

#### Edge Ingress (Traefik)
- **Purpose**: Reverse proxy with automatic HTTPS
- **Certificate Management**: Traefik's built-in ACME resolver (DNS-01 challenge with GoDaddy)
- **Configuration**: Routes defined in `edge_ingress_routes` in host_vars
- **Security**: Automatic HTTP→HTTPS redirect, HSTS headers, security headers middleware

#### Docker Data-Root
- **Default**: `/var/lib/docker` (root partition)
- **Configured**: `/home/deploy/docker` (data partition, owned by deploy user)
- **Bind Mounts**:
  - `/srv` → `/home/deploy/srv` (service data)
  - `/var/log/apps` → `/home/deploy/logs/apps` (application logs)

#### Partition Layout (128GB Drives)
- **Partition 1**: 1GB (FAT32, `/boot`) - Boot partition
- **Partition 2**: 32GB (ext4, `/`) - Root filesystem
- **Partition 3**: ~95GB (ext4, `/home`) - Data partition (Docker, user data, logs)

## Important Patterns and Conventions

### Inventory Management

**Bootstrap Inventory** (`hosts-bootstrap.yml`):
- Uses local IP addresses (192.168.1.x)
- Uses initial user (`ansible_user: armand`)
- Only used for Phase 1 (bootstrap)

**Foundation Inventory** (`hosts-foundation.yml`):
- Uses local IP addresses (may need local network)
- Uses automation user (`ansible_user: ansible`)
- Only used for Phase 2 (foundation)

**Production Inventory** (`hosts-production.yml`):
- Uses Tailscale hostnames (e.g., `rigel.tailb821ac.ts.net` or just `rigel`)
- Uses automation user (`ansible_user: ansible`)
- Used for Phase 3 (production) and all subsequent operations

### Secrets Management

**File**: `ansible/inventories/prod/group_vars/all_secrets.yml` (gitignored)

**Required Variables**:
- `automation_authorized_keys` - SSH keys for ansible user
- `human_users` - List of human users with SSH keys
- `tailscale_authkey` - Tailscale authentication key
- `hostinger_api_token` - Hostinger DNS API token (optional, for edge ingress - **deprecated**, use GoDaddy)
- `godaddy_api_key` - GoDaddy DNS API key (for ACME DNS-01 challenges)
- `godaddy_api_secret` - GoDaddy DNS API secret

**Example Template**: See `all_secrets.yml.example`

### Enabling/Disabling Features

Features are controlled via boolean flags in `group_vars/all.yml` or `host_vars/<hostname>.yml`:

```yaml
# Global defaults (group_vars/all.yml)
enable_tailscale: true
enable_docker: true
enable_fail2ban: true
enable_luks: true
enable_docker_deploy: false  # Enable per-host

# Per-host overrides (host_vars/rigel.yml)
enable_docker_deploy: true
internal_dns_enabled: true
edge_ingress_enabled: true
```

### Role Conditional Execution

Roles check their enable flag and skip if disabled:

```yaml
- name: Skip internal_dns role if not enabled
  when: not (internal_dns_enabled | default(false))
  debug:
    msg: "Skipping internal_dns role (internal_dns_enabled is false)"
```

### Host Key Verification

**Critical Security Pattern**: Every playbook imports `shared/host-key-verification.yml` in pre_tasks:

```yaml
pre_tasks:
  - name: Import host key verification tasks
    import_tasks: shared/host-key-verification.yml
    tags: always
```

**Never disable host key checking** - this prevents MITM attacks.

## Security Rules (from .cursorrules)

**YOU MUST NEVER make changes that have security implications:**
- NO reducing safety checks
- NO ignoring signature or key verifications
- NO disabling host key checking
- NO bypassing authentication mechanisms
- NO weakening encryption or cryptographic verification
- NO removing security validations

**If a change would reduce security:**
1. Reject the change
2. Explain the security risk
3. Suggest a secure alternative

## Testing Strategy

**All testing tools are containerized** - no local Python/pip installation required, only Docker.

### Phase 1: Linting (Immediate)
- `ansible-lint` - Ansible best practices
- `yamllint` - YAML syntax
- `ansible-playbook --syntax-check` - Playbook validation
- **Run**: `./scripts/run-linting.sh`

### Phase 2: Molecule (Short-term)
- Role testing in isolated containers; tests convergence and idempotency
- **Default run** (`./scripts/run-molecule-tests.sh`): firewall_nftables and docker_deploy, end-to-end in a container (docker_deploy includes real Docker-in-Docker)
- **By name only** (`./scripts/run-molecule-tests.sh <role>`): internal_dns and edge_ingress converge their full config but cannot start their systemd-managed CoreDNS/Traefik containers under nested systemd, so they are validated on a real host

### Phase 3: Testinfra (Long-term)
- Production verification on actual servers
- Tests services, packages, configuration
- **Run**: Manually with Docker container + SSH keys

## Common Issues and Solutions

### SMB/NetBIOS Protocol Limitation
- **Issue**: `smb://mpnas.exnada.com` fails with "netbios name too long"
- **Cause**: NetBIOS names limited to 15 characters, FQDNs exceed this
- **Solution**: Use short hostname (`smb://mpnas`) or IP address (`smb://100.120.170.43`)

### DNS Provider for ACME
- **Hostinger API**: Read-only, cannot create DNS records (NOT suitable for ACME)
- **GoDaddy API**: Full DNS management (recommended for ACME DNS-01)
- **Configuration**: Use GoDaddy for DNS management, set `godaddy_api_key` and `godaddy_api_secret`

### Certificate Management: Traefik ACME vs Lego
- **Current Standard**: Traefik's built-in ACME resolver (simpler, automatic renewal)
- **Alternative**: Lego (`cert_issuer` role) - disabled by default
- **When to use Lego**: Multi-service certificates, advanced control requirements
- **Configuration**: Traefik ACME configured in `traefik.yml.j2`, uses GoDaddy DNS-01 challenge

### Firewall Configuration
- **Default policy**: Deny all except explicitly allowed
- **SSH**: Opened by two explicit, narrow paths only — the Tailscale interface and the local LAN subnet (`firewall_local_ssh_subnet`, default 192.168.1.0/24), both key-only. Intentionally NOT in `firewall_allow_tcp_ports` (that list opens ports to all sources). The LAN path is a Tailscale-independent backup so a mesh outage cannot lock out management.
- **Tailscale**: UDP 41641 for initial connection, tailscale0 interface traffic allowed
- **DNS/HTTP/HTTPS**: Only if internal_dns or edge_ingress enabled

### Docker Volume Mounts
- **Always inspect container images** before mounting volumes
- Cannot mount directories over executable files
- Use `docker inspect <image>` to check internal structure

## Development Workflow

### Before Committing
1. Run linting: `./scripts/run-linting.sh`
2. Validate playbooks: `./scripts/validate-playbooks.sh`
3. Test changed roles: `./scripts/run-molecule-tests.sh <role-name>`
4. Verify inventory: `./scripts/verify-inventory-users.sh`

### Adding New Hosts
1. Add to `hosts-bootstrap.yml` (local IP, initial user)
2. Add to `hosts-foundation.yml` (local IP, ansible user)
3. Run Phase 1: `./scripts/run-ansible.sh prod <hostname> bootstrap`
4. Run Phase 2: `./scripts/run-ansible.sh prod <hostname> foundation`
5. Get Tailscale hostname from output
6. Add to `hosts-production.yml` (Tailscale hostname, ansible user)
7. Create `host_vars/<hostname>.yml` with configuration
8. Run Phase 3: `./scripts/run-ansible.sh prod <hostname> production`

### Modifying Roles
1. Make changes to role files
2. Run linting: `./scripts/run-linting.sh`
3. Run role's Molecule tests (if available): `./scripts/run-molecule-tests.sh <role-name>`
4. Test on staging host with `--check` first
5. Deploy to staging: `./scripts/run-ansible.sh prod <hostname> production`
6. Verify with diagnostic scripts

### Creating New Roles
1. Create role directory: `ansible/roles/<role-name>/`
2. Add standard structure: `tasks/main.yml`, `handlers/main.yml`, `templates/`, `defaults/main.yml`
3. Add enable flag check at start of `tasks/main.yml`
4. Add validation tasks for required variables
5. Create Molecule test scenario (optional): `molecule/default/`
6. Add to appropriate playbook phase
7. Document in README.md and this file

## Key Files to Know

### Configuration Files
- `ansible/inventories/prod/group_vars/all.yml` - Global configuration
- `ansible/inventories/prod/group_vars/all_secrets.yml` - Secrets (gitignored)
- `ansible/inventories/prod/host_vars/<hostname>.yml` - Per-host configuration

### Playbook Files
- `ansible/playbooks/<hostname>-bootstrap.yml` - Phase 1 playbook
- `ansible/playbooks/<hostname>-foundation.yml` - Phase 2 playbook
- `ansible/playbooks/<hostname>-production.yml` - Phase 3 playbook

### Key Roles
- `ansible/roles/common_bootstrap/` - Creates automation user, disables password auth
- `ansible/roles/docker_deploy/` - Sets up deploy user and directory structure
- `ansible/roles/internal_dns/` - CoreDNS split-horizon DNS
- `ansible/roles/edge_ingress/` - Traefik reverse proxy with ACME

### Documentation
- `README.md` - Complete deployment guide and troubleshooting
- `scripts/README.md` - Detailed script documentation
- `TESTING_STRATEGY.md` - Testing approach and methodology
- `TESTING_INSTALLATION.md` - Testing tools setup (containerized)
- `docs/lessons-learned.md` - Production troubleshooting insights (if exists)

## Docker-Based Ansible Execution

All Ansible commands run in Docker containers via `scripts/run-ansible.sh`:

**Benefits**:
- Consistent environment across machines
- No local Ansible installation required
- Automatic SSH key mounting
- Proper inventory selection based on phase

**How it works**:
1. Script detects phase (bootstrap, foundation, production)
2. Selects appropriate inventory file
3. Mounts SSH keys from `~/.ssh/`
4. Runs Ansible playbook in `intergalactic-ansible:latest` container
5. Provides phase-specific next steps

## Lessons Learned (Key Production Insights)

### SMB/NetBIOS Limitation
- SMB protocol has 15-character NetBIOS name limit
- FQDNs like `mpnas.exnada.com` cannot be used for SMB
- Use short hostnames or IP addresses instead

### DNS Split-Horizon
- CoreDNS can serve zone authoritatively while forwarding unknown queries
- Use `forward` plugin inside zone block for external domain resolution
- Enables private hosts (Tailscale IPs) + public hosts (via upstream DNS)

### Certificate Management
- Traefik's built-in ACME is simpler than separate cert_issuer (lego)
- Must use public DNS resolvers for ACME verification (not Tailscale DNS)
- GoDaddy API works for ACME DNS-01, Hostinger does not (read-only)

### Security Headers
- Some backends send restrictive CSP headers that break reverse proxy access
- `X-Content-Type-Options: nosniff` requires correct Content-Type headers
- May need to remove problematic headers for compatibility with misconfigured backends

### Container Mounts
- Cannot mount directories over executable files in containers
- Always inspect container image structure before defining mounts
- Use correct internal mount points

## When Working With This Codebase

### Always Remember
1. **Three-phase model** - Bootstrap → Foundation → Production
2. **Inventory files differ by phase** - Bootstrap uses initial user + local IP, Foundation uses ansible user + local IP, Production uses ansible user + Tailscale hostname
3. **Security is non-negotiable** - Never disable host key checking, never weaken authentication
4. **Testing is containerized** - No local installation needed, just Docker
5. **Roles have dependencies** - Order matters in production playbooks
6. **Secrets are gitignored** - All sensitive data in `all_secrets.yml`

### When Modifying Code
1. Check if change affects security (if yes, stop and discuss)
2. Run linting before committing
3. Test role changes with Molecule (if tests exist)
4. Validate playbook syntax
5. Test with `--check` mode first
6. Document significant changes in README.md

### When Troubleshooting
1. Check role execution order (dependencies)
2. Verify enable flags in host_vars
3. Check Ansible output for skipped tasks
4. Use diagnostic scripts (verify-reverse-proxy.sh, diagnose-reverse-proxy.sh)
5. Verify Tailscale connectivity for production phase
6. Check secrets are properly configured in all_secrets.yml
7. Consult README.md "Lessons Learned" section for known issues
