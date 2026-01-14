# Fix DNS Nameserver Issue

## Problem

Lego is trying to query `rigel.exnada.com` as an authoritative nameserver for `exnada.com`, which causes certificate issuance to fail with:

```
authoritative nameservers: DNS call error: dial udp: lookup rigel.exnada.com. on 100.100.100.100:53: no such host
```

## Root Cause

The DNS zone for `exnada.com` in GoDaddy likely has incorrect NS (nameserver) records pointing to `rigel.exnada.com`. This is wrong because:

1. `rigel.exnada.com` is not a nameserver - it's just a hostname
2. GoDaddy should be the authoritative nameserver for `exnada.com`
3. The internal DNS (CoreDNS) on rigel is for **private subdomains only**, not the root domain

## Solution

### Step 1: Check Current DNS Configuration

Run the diagnostic script on rigel:

```bash
scp scripts/check-dns-nameservers.sh rigel:/tmp/
ssh rigel "chmod +x /tmp/check-dns-nameservers.sh && /tmp/check-dns-nameservers.sh"
```

This will show you what nameservers are currently configured.

### Step 2: Fix NS Records in GoDaddy

1. **Log into GoDaddy DNS Management:**
   - Go to: https://dcc.godaddy.com/manage/exnada.com/dns
   - Or: https://www.godaddy.com → My Products → DNS

2. **Check NS Records:**
   - Look for any NS (Nameserver) records
   - **Remove any NS records pointing to `rigel.exnada.com` or any other internal hostname**

3. **Ensure Only GoDaddy Nameservers:**
   - The NS records should only point to GoDaddy's nameservers, such as:
     - `ns1.godaddy.com`
     - `ns2.godaddy.com`
     - Or similar GoDaddy nameservers

4. **Save Changes:**
   - DNS changes can take up to 48 hours to propagate, but usually happen within minutes

### Step 3: Verify Fix

After updating DNS, verify:

```bash
# Check NS records (should NOT include rigel.exnada.com)
dig @8.8.8.8 exnada.com NS +short

# Should show GoDaddy nameservers like:
# ns1.godaddy.com
# ns2.godaddy.com
```

### Step 4: Retry Certificate Issuance

Once DNS is fixed, retry certificate issuance:

```bash
ssh rigel "sudo /tmp/run-cert-issuance.sh staging"
```

## Technical Details

### Why This Happens

- The `internal_dns` role creates an authoritative DNS zone for `exnada.com` on rigel
- This is **only for private subdomains** (mpnas.exnada.com, aispector.exnada.com, etc.)
- The root domain `exnada.com` should still be managed by GoDaddy
- If NS records point to rigel.exnada.com, lego tries to verify DNS by querying rigel, which fails

### Workaround (Already Applied)

The scripts have been updated to:
- Use `--dns.propagation-disable-ans` to disable authoritative nameserver checks
- Use `--dns.resolvers "8.8.8.8:53,8.8.4.4:53"` to use Google DNS for verification

This workaround allows certificate issuance even with incorrect NS records, but **you should still fix the DNS records** for proper DNS management.

## Prevention

- **Never create NS records** pointing to internal hosts in GoDaddy DNS
- The `internal_dns` role is for **private subdomains only**, not the root domain
- GoDaddy should always be the authoritative nameserver for the root domain
