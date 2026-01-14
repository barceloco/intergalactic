# Container Restart Runbook

## Prerequisites

- SSH access to the host
- sudo/root privileges
- Docker installed and running

## Restart CoreDNS

### Steps

1. **Check current status**
   ```bash
   systemctl status coredns
   docker ps --filter name=coredns
   ```

2. **Restart via systemd** (recommended)
   ```bash
   sudo systemctl restart coredns
   ```

3. **Verify restart**
   ```bash
   systemctl status coredns
   docker ps --filter name=coredns
   ```

4. **Test DNS resolution**
   ```bash
   dig @127.0.0.1 exnada.com
   ```

### Alternative: Direct Docker Restart

```bash
cd /opt/coredns
docker compose restart
```

## Restart Traefik

### Steps

1. **Check current status**
   ```bash
   systemctl status traefik
   docker ps --filter name=traefik
   ```

2. **Restart via systemd** (recommended)
   ```bash
   sudo systemctl restart traefik
   ```

3. **Verify restart**
   ```bash
   systemctl status traefik
   docker ps --filter name=traefik
   ```

4. **Test HTTPS endpoint**
   ```bash
   curl -k -H "Host: aispector.exnada.com" https://localhost/health
   ```

### Alternative: Direct Docker Restart

```bash
cd /opt/traefik
docker compose restart
```

## Verification

After restarting containers:

1. **Check container status**: `docker ps`
2. **Check systemd services**: `systemctl status <service>`
3. **Test functionality**: DNS resolution, HTTPS endpoints
4. **Check logs**: `docker logs <container>`

## Rollback

If restart causes issues:

1. **Check logs**: `docker logs <container>`
2. **Verify configuration**: Check config files
3. **Restore from backup**: If configuration was changed
4. **Contact support**: If issue persists
