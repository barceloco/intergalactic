# DNS Troubleshooting Guide

## Common Issues

### Issue: DNS Resolution Fails

**Symptoms**:
- DNS queries timeout
- Services cannot resolve hostnames
- `dig` commands fail

**Diagnosis**:
```bash
# Check if CoreDNS container is running
docker ps --filter name=coredns

# Check CoreDNS logs
docker logs coredns

# Test DNS resolution
dig @127.0.0.1 exnada.com

# Check systemd service status
systemctl status coredns
```

**Solutions**:
1. **Container not running**: Restart CoreDNS
   ```bash
   systemctl restart coredns
   ```

2. **Port 53 in use**: Check for conflicting services
   ```bash
   netstat -tuln | grep :53
   sudo lsof -i :53
   ```

3. **Configuration error**: Check Corefile and zone file
   ```bash
   cat /opt/coredns/Corefile
   cat /opt/coredns/db.exnada.com
   ```

4. **Docker issues**: Check Docker daemon
   ```bash
   systemctl status docker
   docker info
   ```

### Issue: DNS Returns Wrong IP

**Symptoms**:
- DNS resolves to incorrect IP
- Services cannot connect

**Diagnosis**:
```bash
# Check DNS response
dig @127.0.0.1 vega.exnada.com

# Check zone file
cat /opt/coredns/db.exnada.com

# Verify Tailscale IP
tailscale ip -4
```

**Solutions**:
1. **Update zone file**: Regenerate with correct IPs
2. **Reload CoreDNS**: Restart to pick up changes
   ```bash
   systemctl restart coredns
   ```

### Issue: External DNS Not Working

**Symptoms**:
- Internal DNS works, external fails
- Cannot resolve external domains

**Diagnosis**:
```bash
# Test external DNS
dig @127.0.0.1 google.com

# Check upstream DNS servers
cat /opt/coredns/Corefile | grep forward
```

**Solutions**:
1. **Check upstream DNS**: Verify 8.8.8.8 and 8.8.4.4 are reachable
2. **Network connectivity**: Check internet connection
3. **Firewall**: Verify DNS forwarding is allowed

## Diagnostic Commands

```bash
# Check CoreDNS status
systemctl status coredns
docker ps --filter name=coredns

# Test DNS resolution
dig @127.0.0.1 exnada.com
dig @127.0.0.1 vega.exnada.com

# Check DNS logs
docker logs coredns
journalctl -u coredns

# Verify configuration
cat /opt/coredns/Corefile
cat /opt/coredns/db.exnada.com

# Check port binding
netstat -tuln | grep :53
```

## Log Locations

- **Container logs**: `docker logs coredns`
- **Systemd logs**: `journalctl -u coredns`
- **Configuration**: `/opt/coredns/Corefile`, `/opt/coredns/db.exnada.com`
