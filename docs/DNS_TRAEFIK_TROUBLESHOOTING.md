# DNS and Traefik Troubleshooting Summary

**Date**: 2026-01-14
**Issue**: aispector.exnada.com, dev.exnada.com, mpnas.exnada.com not accessible

## 🎯 Root Cause Identified

**The infrastructure on rigel is working correctly.** The problem was **Tailscale split-horizon DNS was pointing to the OLD rigel IP address.**

### The Issue

When rigel was rebuilt/reinstalled, it received a new Tailscale IP:
- **Old rigel IP**: `100.72.27.93` (rigel-old in Tailscale status)
- **New rigel IP**: `100.116.21.120` (current rigel)

**The Tailscale Admin Console still had the DNS nameserver configured to use the OLD IP**, causing all DNS queries to fail.

### Why This Happens

When you reinstall a host:
1. Tailscale assigns a new IP address
2. The old Tailscale node becomes "offline"
3. **BUT**: Split DNS configuration in Tailscale Admin Console is NOT automatically updated
4. Result: DNS queries route to the old, offline IP

### What's Working ✅

1. **CoreDNS on rigel** - Running and resolving correctly
   - `dig @100.116.21.120 aispector.exnada.com` → `100.116.21.120` ✅
   - `dig @100.116.21.120 dev.exnada.com` → `100.116.21.120` ✅
   - `dig @100.116.21.120 mpnas.exnada.com` → `100.120.170.43` ✅

2. **Traefik on rigel** - Running with valid Let's Encrypt certificates
   - Listening on ports 80/443 ✅
   - Valid certificates for both aispector.exnada.com and dev.exnada.com ✅
   - Issued: Jan 13, 2026; Expires: Apr 13, 2026 ✅

3. **Backend for aispector.exnada.com** - vega:8000 running (uvicorn) ✅

### What's NOT Working ❌

1. **Tailscale MagicDNS not forwarding** - `dig @100.100.100.100 aispector.exnada.com` times out
   - Your Mac/clients use MagicDNS (100.100.100.100) as primary DNS
   - MagicDNS doesn't know to forward `exnada.com` queries to rigel
   - Result: DNS resolution fails → Safari/curl cannot connect

2. **Backend for dev.exnada.com missing** - No service running on rigel:8000
   - Traefik is configured to proxy to `http://rigel:8000`
   - No service listening on that port
   - Result: Even after DNS is fixed, dev.exnada.com will timeout

## 🔧 Required Actions

### Action 1: Update Tailscale Split DNS to New IP (REQUIRED - Manual)

**After running the foundation playbook, you MUST update Tailscale DNS settings:**

1. Go to: https://login.tailscale.com/admin/dns
2. Look for "Nameservers" or "Split DNS" section
3. **IMPORTANT**: Check if an old configuration exists and delete it
4. Add/update nameserver configuration:
   - **Option A (Recommended)**: Split DNS
     - Restricted to domain: `exnada.com`
     - Nameserver: `100.116.21.120` (rigel's NEW Tailscale IP)
   - **Option B**: Global nameserver
     - Just enter: `100.116.21.120`

5. Wait 1-2 minutes for propagation
6. Verify: `make check-tailscale`

**Pro Tip**: After running the foundation playbook, it prints rigel's Tailscale IP. Use that IP for DNS configuration.

### Action 2: Deploy Backend Service for dev.exnada.com

**Question**: What service should run on rigel:8000?

Options:
- Docker container?
- Systemd service?
- Should dev.exnada.com point elsewhere?

### Action 3: Fix cert_issuer_ca_server Variable (Minor - Can Do After)

Template references variable from disabled role. Low priority, won't help until DNS works.

## 📊 New Tools Created

### Makefile

```bash
make help              # Show all commands
make diagnose          # Run all diagnostics
make check-dns         # Check CoreDNS
make check-traefik     # Check Traefik
make check-certs       # Check ACME certificates
make check-tailscale   # Check Tailscale DNS
make deploy-traefik    # Quick deploy Traefik config
make lint              # Run linting
make test              # Run all tests
```

### Scripts (All without Python/jq one-liners)

1. **scripts/diagnose-dns-traefik.sh** - Complete diagnostics
2. **scripts/check-tailscale-dns.sh** - Tailscale DNS check
3. **scripts/check-acme-certificates.sh** - Certificate status
4. **scripts/quick-deploy-traefik.sh** - Fast Traefik deployment

## 🧪 Testing After Tailscale DNS is Configured

```bash
# 1. Check Tailscale DNS configuration
make check-tailscale

# 2. Test DNS resolution
dig aispector.exnada.com

# 3. Test HTTPS endpoint
curl --max-time 5 https://aispector.exnada.com/health

# 4. Check certificates
make check-certs
```

Expected results after DNS is fixed:
- `dig aispector.exnada.com` returns `100.116.21.120` instantly
- `curl https://aispector.exnada.com/health` returns HTTP 200
- Safari can access aispector.exnada.com successfully

## 📝 About mpnas.exnada.com

**Status**: DNS-only (not proxied through Traefik)

- DNS resolves to: `100.120.170.43` (mpnas's own IP) ✅
- Intentionally NOT proxied (removed from edge_ingress_routes) ✅
- Direct access via `https://mpnas.exnada.com:5001` or `smb://mpnas`
- Will show certificate warnings (expected - mpnas has self-signed cert)

## 🏗️ Architecture Summary

```
Client (Safari)
  → Tailscale MagicDNS (100.100.100.100) [❌ NOT FORWARDING]
    → Should forward to rigel CoreDNS (100.116.21.120) [✅ WORKING]
      → Returns rigel IP for aispector/dev, mpnas IP for mpnas
        → Traefik on rigel:443 [✅ WORKING, VALID CERTS]
          → Proxies to backend [✅ vega:8000 works, ❌ rigel:8000 missing]
```

**The break is at step 1** - Tailscale MagicDNS not forwarding.

## 🚦 Next Steps

1. **You**: Configure Tailscale split DNS (must be done in web console)
2. **You**: Let me know when configured
3. **Me**: Verify DNS is working: `make check-tailscale`
4. **Us**: Discuss what should run on rigel:8000 for dev.exnada.com
5. **Me**: Apply minor template fix for cert_issuer_ca_server
6. **Me**: Final end-to-end verification

## 🔍 Diagnostic Commands Reference

```bash
# Quick checks
make check-tailscale    # Tailscale DNS config
make check-dns          # CoreDNS status
make check-certs        # Certificate status

# Full diagnostics
make diagnose           # All checks

# Direct tests
dig @100.116.21.120 aispector.exnada.com    # Test CoreDNS directly
dig @100.100.100.100 aispector.exnada.com   # Test via Tailscale
curl https://aispector.exnada.com/health    # Test HTTPS endpoint
```

## 📚 Important Notes

- **No changes made to vega or mpnas** (per your instruction) ✅
- **No Python one-liners in scripts** (per your preference) ✅
- **All scripts managed via Makefile** ✅
- **Certificates are valid** - this is NOT a certificate issue
- **Traefik is working** - this is NOT a reverse proxy issue
- **This is purely a DNS routing issue** at the Tailscale level
