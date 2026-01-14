# Archived Scripts

This directory contains scripts that have been archived because they are no longer actively used in the current infrastructure.

## Why These Scripts Are Archived

Scripts are archived (not deleted) for several reasons:
1. **Historical Reference**: They document troubleshooting approaches used during development
2. **Learning Resource**: They show how specific problems were solved
3. **Potential Reuse**: May be useful if switching back to deprecated approaches
4. **Documentation**: Code examples for future similar problems

## Archive Categories

### cert-issuer/
Scripts related to the `cert_issuer` role (lego-based certificate management).

**Why Archived**: The project switched from lego (cert_issuer role) to Traefik's built-in ACME resolver for certificate management. Traefik ACME is simpler, more integrated, and handles renewal automatically.

**When to Restore**: If you need to manage certificates for non-Traefik services or prefer file-based certificate management over Traefik's acme.json approach.

**Scripts**:
- `diagnose-cert-issuer.sh` - Diagnose lego container issues
- `diagnose-lego-mount.sh` - Debug lego volume mount problems
- `inspect-lego-image.sh` - Inspect lego Docker image structure
- `run-cert-issuance-docker.sh` - Run lego in Docker
- `run-cert-issuance.sh` - Certificate issuance wrapper
- `README-cert-issuer.md` - Original documentation

### troubleshooting/
One-time troubleshooting scripts created during development and production deployment.

**Why Archived**: These scripts addressed specific issues that have been resolved and incorporated into Ansible roles. They are preserved as documentation of the troubleshooting process.

**When to Restore**: If you encounter similar issues or need to understand the original problem-solving approach.

**Scripts**:
- `fix-aispector-port-mapping.sh` - Fixed specific service port configuration
- `fix-backend-url-properly.sh` - Resolved backend URL resolution
- `fix-dev-exnada-backend.sh` - Development environment fix
- `fix-traefik-backend-url.sh` - Traefik backend URL configuration
- `fix-traefik-dev-config.sh` - Development Traefik configuration
- `fix-traefik-dns-now.sh` - Emergency DNS fix (now in playbooks)
- `fix-yaml-syntax.sh` - YAML syntax repair utility
- `create-traefik-dev-config.sh` - Development helper
- `inspect-and-fix-traefik-config.sh` - Debug script
- `find-traefik-config.sh` - Configuration location helper

## How to Restore

If you need to restore any of these scripts:

```bash
# Copy back to scripts directory
cp archived/<category>/<script-name> ../

# Make executable
chmod +x ../<script-name>

# Update documentation
# Add entry to scripts/README.md if it will be actively maintained
```

## Maintenance

- **Do not delete these scripts** without documenting why in this README
- **Add new archived scripts** to the appropriate category with explanation
- **Update this README** when archiving new scripts
- **Review annually** to determine if any scripts should be permanently removed

---

Last Updated: 2026-01-13
Archived During: Phase 1 codebase streamlining (consolidation effort)
