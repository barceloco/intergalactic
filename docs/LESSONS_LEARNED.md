# Lessons Learned: Production Issues and Solutions

This document consolidates critical issues encountered during production deployment and their solutions. Use this as a quick reference when troubleshooting similar problems.

## Table of Contents

1. [DNS and Networking](#dns-and-networking)
2. [Certificates and HTTPS](#certificates-and-https)
3. [Reverse Proxy Configuration](#reverse-proxy-configuration)
4. [Deployment and Automation](#deployment-and-automation)
5. [Diagnostic Tools](#diagnostic-tools)

---

## DNS and Networking

### Issue: Services Timeout Despite Valid Certificates

**Date**: 2026-01-14
**Symptoms**:
- `curl https://aispector.exnada.com` times out
- Safari shows "cannot connect to server"
- Direct IP access (`curl https://100.116.21.120`) works
- Certificates are valid and present

**Root Cause**:
Tailscale split-horizon DNS was pointing to OLD rigel IP (`100.72.27.93`) instead of new IP (`100.116.21.120`).

**Why This Happens**:
1. When you reinstall/rebuild a Tailscale host, it gets a NEW Tailscale IP
2. The old node shows as "offline" in `tailscale status`
3. **Tailscale Admin Console DNS settings are NOT automatically updated**
4. DNS queries route to the old, offline IP → timeout

**Solution**:
1. After running foundation playbook, note the Tailscale IP from output
2. Go to https://login.tailscale.com/admin/dns
3. Delete any old DNS nameserver configuration
4. Add/update split DNS:
   - Domain: `exnada.com`
   - Nameserver: `<new-tailscale-ip>` (e.g., `100.116.21.120`)
5. Wait 1-2 minutes for propagation
6. Verify: `make check-tailscale`

**Prevention**:
- Foundation playbook now displays Tailscale IP and reminder message
- Always update Tailscale DNS settings after reinstalling a host
- Use `tailscale status` to find current IPs before configuring DNS

**Diagnostic Commands**:
```bash
# Check Tailscale status and IPs
tailscale status | grep -E "(rigel|vega|mpnas)"

# Test CoreDNS directly
dig @100.116.21.120 aispector.exnada.com

# Test via Tailscale MagicDNS
dig @100.100.100.100 aispector.exnada.com

# Full diagnostic
make check-tailscale
```

---

### Issue: SMB/NetBIOS Name Length Limitation

**Symptoms**:
- `smb://mpnas.exnada.com` fails with "netbios name too long"
- Shorter names like `smb://mpnas` work fine

**Root Cause**:
NetBIOS protocol limits hostnames to 15 characters. FQDNs exceed this limit.

**Solution**:
- Use short hostname: `smb://mpnas`
- OR use IP address: `smb://100.120.170.43`
- DNS-only configuration (no Traefik proxy) for direct access

**Reference**: README.md "Lessons Learned" section

---

### Issue: Operator Machine Loses Direct Tailscale Traffic to a Second VPN

**Symptoms**:
- `ssh <host>` or `curl https://<service>.exnada.com` from your workstation hang and time out, yet `tailscale ping <host>` still succeeds (reporting `via DERP`, "direct connection not established").
- `dig <host>.exnada.com` may also time out when MagicDNS (`100.100.100.100`) is affected the same way.
- `tailscale status` warns `client version "X" != tailscaled server version "Y"`.

**Root Cause**:
A second full-tunnel VPN (e.g. a corporate or university client) is active alongside Tailscale. It holds the default route and installs a packet filter that drops traffic on other tunnels, so DERP-relayed control traffic (which looks like ordinary HTTPS to the relay) keeps working while direct TCP over the Tailscale tunnel is blocked. Quitting and reopening the Tailscale menu-bar app does not fix it — that does not restart the underlying daemon.

**Solution**:
Disconnect the other VPN (or configure it to exclude `100.64.0.0/10` and `100.100.100.100` from its tunnel), then retest. Full guide: `docs/troubleshooting/tailscale-client-connectivity.md`.

**Prevention**:
- When SSH/HTTPS to the fleet times out but `tailscale ping` works, suspect a client-side VPN conflict on your own machine *before* touching any fleet host.

---

## Certificates and HTTPS

### Issue: Certificate Issuance Using Wrong Let's Encrypt Server

**Symptoms**:
- Browsers show "invalid certificate" warnings
- Certificates issued by Let's Encrypt Staging instead of Production

**Root Cause**:
Template variable conflict - `traefik.yml.j2` referenced `cert_issuer_ca_server` from disabled `cert_issuer` role.

**Solution**:
- Created dedicated variable: `edge_ingress_acme_staging` (default: `false`)
- Updated template to use edge_ingress-specific variable
- Ensures production certificates unless explicitly testing

**Fixed Files**:
- `ansible/roles/edge_ingress/templates/traefik.yml.j2`
- `ansible/roles/edge_ingress/defaults/main.yml`

**Prevention**:
- Use role-specific variables to avoid naming conflicts
- Never reference variables from disabled roles

---

### Issue: GoDaddy API Permissions for ACME

**Symptoms**:
- Certificate issuance fails
- Traefik logs show DNS challenge errors

**Root Cause**:
API keys must have DNS management permissions. Read-only keys cannot create TXT records for ACME challenges.

**Solution**:
- Use GoDaddy API key with full DNS management permissions
- Configure in `all_secrets.yml`:
  ```yaml
  godaddy_api_key: "<key-with-dns-permissions>"
  godaddy_api_secret: "<secret>"
  ```

**Alternative Providers**:
- Hostinger API is read-only → NOT suitable for ACME
- GoDaddy, Cloudflare, Route53 work well for DNS-01 challenges

---

### Change: Edge Ingress Serves All Hosts From One Wildcard Certificate

**Context**:
Each Traefik router used to request its own certificate via `certResolver: letsencrypt`. The dynamic config now defines a default TLS store with a `defaultGeneratedCert` for `*.exnada.com` (apex as SAN), and every router uses `tls: {}` to share it.

**Why**:
One wildcard cert covers every current single-level host (docgen, dev, demo, callosal, immich, mpnas, aispector), cutting per-host ACME issuance and renewals down to a single certificate.

**Caveats**:
- A wildcard only covers one subdomain level; a multi-level host (e.g. `a.b.exnada.com`) would need its own cert or a nested wildcard.
- Issuance now concentrates risk: if the single `*.exnada.com` DNS-01 challenge fails, routers fall back to Traefik's self-signed default and **all** hosts show TLS warnings until it succeeds. After deploying, verify HTTPS on several hosts and watch Traefik logs for the ACME result. Roll back with `git revert` of the template change if needed.

**Files**:
- `ansible/roles/edge_ingress/templates/dynamic.yml.j2` — default TLS store plus `tls: {}` on routers.
- `ansible/roles/edge_ingress/templates/traefik.yml.j2` — `letsencrypt` resolver (GoDaddy DNS-01).

---

## Reverse Proxy Configuration

### Issue: Backend Services Not Responding

**Symptoms**:
- Valid HTTPS certificate
- Connection times out or shows "503 Service Unavailable"
- Traefik logs show backend health check failures

**Root Cause**:
No service running on the configured backend port.

**Example**: `dev.exnada.com` configured to proxy to `rigel:8000`, but no service listening on that port.

**Solution**:
1. Verify backend service is running:
   ```bash
   ssh rigel "ss -tlnp | grep :8000"
   ```
2. Deploy/start the required backend service
3. Verify health check endpoint exists (`/health`)
4. Check Traefik dynamic configuration:
   ```bash
   ssh rigel "cat /opt/traefik/dynamic.yml"
   ```

**Prevention**:
- Document what should run on each port
- Use health checks to detect backend failures
- Monitor Traefik logs for backend connectivity issues

---

### Issue: Synology DSM Behind Reverse Proxy

**Symptoms**:
- CSS/JS files don't load
- Content-Type headers are incorrect
- Page renders without styling

**Root Cause**:
Synology sends `text/html` Content-Type for CSS/JS files. `X-Content-Type-Options: nosniff` header prevents browsers from parsing incorrectly-typed content.

**Solution**:
- Use `security-headers-no-nosniff` middleware
- Remove `X-Content-Type-Options: nosniff` header
- Allow browser to infer content type from file content

**Configuration**:
```yaml
edge_ingress_routes:
  - host: mpnas.exnada.com
    backend: http://mpnas:5000
    force_html_content_type: true  # Uses security-headers-no-nosniff
```

**Note**: For mpnas, we ultimately chose DNS-only (no proxy) for direct access.

---

## Deployment and Automation

### Issue: Deploy User SSH Key Not Added to GitHub

**Symptoms**:
- Deploy user cannot clone private repositories
- `git clone` fails with permission denied

**Solution**:
Production playbook now displays deploy user's SSH public key with instructions to add it to GitHub.

**Steps**:
1. Run production playbook (or docker_deploy role)
2. Copy the displayed SSH public key
3. Add to GitHub:
   - Repository: https://github.com/<org>/<repo>/settings/keys
   - OR User account: https://github.com/settings/keys

**Prevention**:
- Playbook automatically displays key after creation
- Instructions included in playbook output

---

### Issue: Docker Containers Cannot Resolve Tailscale Hostnames

**Symptoms**:
- Traefik cannot connect to backends
- `docker exec traefik ping vega` fails

**Root Cause**:
Docker daemon uses its own DNS resolver by default, which doesn't know about Tailscale MagicDNS.

**Solution**:
Configure Docker daemon to use CoreDNS:
```yaml
docker_deploy_dns_servers:
  - 127.0.0.1  # CoreDNS (for Tailscale hostname resolution)
  - 8.8.8.8    # Fallback to Google DNS
```

**Files**:
- Configuration in `host_vars/rigel.yml`
- Applied by `docker_deploy` role to `/etc/docker/daemon.json`

---

### Issue: Containerized Ansible Deploy Fails Host-Key Verification

**Symptoms**:
- `./scripts/run-ansible.sh prod <host> production` fails in `pre_tasks` with `UNREACHABLE! ... Host key verification failed`.
- The `ssh-keyscan` step fetched no key (its `ssh_keyscan_output.stdout_lines | length > 0` assertion is false), so `known_hosts` stayed empty.

**Root Cause**:
The playbook addresses hosts by their Tailscale MagicDNS FQDN (`<host>.tailb821ac.ts.net`). The Dockerized ansible run has no MagicDNS of its own, so when the operator's Tailscale client is degraded (see "Operator Machine Loses Direct Tailscale Traffic to a Second VPN" above), `ssh-keyscan <fqdn>` inside the container returns nothing, and strict host-key checking then correctly refuses the connection. Note the operator's `~/.ssh/known_hosts` frequently trusts only the short name (`<host>`), not the FQDN the inventory uses.

**Solution**:
- Fix the underlying Tailscale client connectivity first, then deploy once the tailnet is stable.
- Do **not** disable host-key checking to force it through — that removes MITM protection and is prohibited by the project's security rules.

**Prevention**:
- Treat `Host key verification failed` at deploy time as a symptom of degraded client-side Tailscale, not a reason to weaken SSH security.

---

### Cross-Repo: docgen Admin Allow-List Wiped by an Empty Compose Env Var

**Context**:
docgen runs on vega (this fleet) behind edge_ingress at `docgen.exnada.com`. A `docker-compose.yml` `${DOCGEN_ADMINS:-}` passthrough silently overrode the app's built-in admin default with an explicit empty string whenever the deployment `.env` did not set it, locking out all admins after a redeploy or reboot.

**Where documented**:
Full incident, diagnosis, and fix live in the **docgen** repo: `README.md` → "Tailscale and access control" → "Troubleshooting: ... not on the allow-list", and `docs/lessons-learned.md`.

**Fleet-side takeaway**:
- vega tracks docgen's `main` branch; deploys are `git pull` + `make up` as the `deploy` user. The only host-local, non-git file is the gitignored `.env`. Containers use `restart: unless-stopped` with Docker enabled on boot, so the service returns after a reboot with its correct configuration.

---

## Diagnostic Tools

### Makefile Commands

Quick access to common diagnostic operations:

```bash
make help              # Show all available commands
make diagnose          # Run all diagnostics (DNS, Traefik, Tailscale)
make check-tailscale   # Check Tailscale DNS configuration
make check-dns         # Check CoreDNS status and resolution
make check-traefik     # Check Traefik status and logs
make check-certs       # Check ACME certificate status
make deploy-traefik    # Quick deploy Traefik configuration
make lint              # Run all linting checks
make test              # Run all tests
```

### Diagnostic Scripts

All scripts use pure bash (no Python/jq dependencies):

1. **`scripts/check-tailscale-dns.sh`**
   - Tests Tailscale MagicDNS forwarding to CoreDNS
   - Identifies DNS routing issues
   - Provides actionable fix instructions

2. **`scripts/diagnose-dns-traefik.sh`**
   - Complete DNS and Traefik diagnostics
   - Service status, logs, certificates
   - Backend connectivity tests

3. **`scripts/check-acme-certificates.sh`**
   - Lists certificates in acme.json
   - Tests certificate validity via HTTPS
   - Shows certificate expiration dates

4. **`scripts/quick-deploy-traefik.sh`**
   - Fast Traefik configuration deployment
   - Skips full playbook run
   - Restarts service and shows logs

### Quick Diagnostic Flow

When services aren't accessible:

```bash
# 1. Check Tailscale DNS configuration
make check-tailscale

# 2. If DNS is broken, fix in Tailscale Admin Console

# 3. Test DNS resolution
dig aispector.exnada.com

# 4. Test HTTPS endpoint
curl --max-time 5 https://aispector.exnada.com/health

# 5. Check backend connectivity
ssh rigel "curl --max-time 5 http://vega:8000/health"

# 6. Check Traefik logs
ssh rigel "docker logs traefik 2>&1 | tail -50"

# 7. Check certificates
make check-certs
```

---

## Architecture Patterns

### Split-Horizon DNS with CoreDNS

**Purpose**: Resolve internal hosts to Tailscale IPs, forward external queries upstream.

**Implementation**:
- Template plugin for specific internal hosts (authoritative)
- Forward plugin for all other queries (recursive)
- Runs on rigel, configured in Tailscale Admin Console

**Configuration**: `ansible/roles/internal_dns/`

### DNS-Only vs Reverse Proxy

**When to use DNS-only** (like mpnas):
- Service has its own HTTPS with self-signed certificate
- No need for Let's Encrypt certificate
- SMB/NetBIOS limitations
- Direct access preferred

**When to use Reverse Proxy** (like aispector, dev):
- Need Let's Encrypt certificates
- HTTPS termination required
- Backend is HTTP-only
- Health checks and load balancing needed

### Docker Data-Root Configuration

**Default**: `/var/lib/docker` (root partition - limited space)
**Configured**: `/home/deploy/docker` (data partition - more space)

**Bind Mounts**:
- `/srv` → `/home/deploy/srv` (service data)
- `/var/log/apps` → `/home/deploy/logs/apps` (application logs)

**Permissions**:
- Docker data-root: `root:docker` with `750` permissions
- Service data/logs: `deploy:deploy` with `755` permissions

---

## Common Error Patterns

### "Could not resolve host"
- **Check**: Tailscale DNS configuration
- **Tool**: `make check-tailscale`
- **Fix**: Update Tailscale Admin Console DNS settings

### "Connection timeout"
- **Check**: Backend service is running
- **Tool**: `ssh <host> "ss -tlnp | grep :<port>"`
- **Fix**: Start backend service

### "SSL certificate problem"
- **Check**: Certificate validity and CA
- **Tool**: `make check-certs`
- **Fix**: Check ACME configuration, GoDaddy API keys

### "503 Service Unavailable"
- **Check**: Backend health checks failing
- **Tool**: Traefik logs, curl to backend
- **Fix**: Verify backend service and health endpoint

---

## Prevention Checklist

### After Reinstalling a Host:

- [ ] Note new Tailscale IP from foundation playbook output
- [ ] Update Tailscale Admin Console DNS configuration
- [ ] Update `hosts-production.yml` with new Tailscale hostname
- [ ] Verify DNS resolution: `make check-tailscale`
- [ ] Test HTTPS endpoints: `curl https://<service>.exnada.com/health`

### Before Deploying New Services:

- [ ] Define backend service and port
- [ ] Configure health check endpoint
- [ ] Add to `edge_ingress_routes` in host_vars
- [ ] Deploy Traefik configuration: `make deploy-traefik`
- [ ] Verify certificate issuance: `make check-certs`
- [ ] Test end-to-end: Browser + curl

### Regular Maintenance:

- [ ] Monitor certificate expiration (30 days before expiry)
- [ ] Check Traefik logs for errors
- [ ] Verify backend health checks
- [ ] Review Tailscale DNS configuration
- [ ] Test DNS resolution from clients

---

## Additional Resources

- **README.md**: Complete deployment guide and three-phase model
- **CLAUDE.md**: Claude Code integration and project instructions
- **TESTING_STRATEGY.md**: Testing approach and methodology
- **DNS_TRAEFIK_TROUBLESHOOTING.md**: Detailed DNS troubleshooting from 2026-01-14 investigation

---

*This document is continuously updated as new issues are discovered and resolved. When encountering a new production issue, add it here for future reference.*
