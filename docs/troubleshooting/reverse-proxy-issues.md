# Reverse Proxy Troubleshooting Guide

## Common Issues

### Issue: 503 Service Unavailable

**Symptoms**:
- HTTPS requests return 503
- Backend services appear down

**Diagnosis**:
```bash
# Check Traefik container
docker ps --filter name=traefik
docker logs traefik | tail -50

# Test backend connectivity
docker exec traefik wget -qO- --timeout=5 http://vega.tailb821ac.ts.net:8000/health

# Check Traefik API
curl http://localhost:8080/api/http/services
```

**Solutions**:
1. **Backend not running**: Start backend service
2. **Network issue**: Check Tailscale connectivity
3. **DNS resolution**: Verify backend hostname resolves
4. **Health check failing**: Check backend health endpoint

### Issue: Certificate Errors

**Symptoms**:
- Browser shows certificate errors
- HTTPS connections fail

**Diagnosis**:
```bash
# Check certificate
openssl s_client -connect aispector.exnada.com:443 -servername aispector.exnada.com

# Check ACME file
ls -la /opt/traefik/acme.json

# Check Traefik logs for certificate errors
docker logs traefik | grep -i cert
```

**Solutions**:
1. **Certificate expired**: Renew certificate
   ```bash
   # Traefik should auto-renew, but can trigger manually
   docker exec traefik touch /opt/traefik/dynamic.yml
   ```

2. **ACME file permissions**: Fix permissions
   ```bash
   chmod 600 /opt/traefik/acme.json
   ```

3. **DNS challenge failure**: Check GoDaddy API credentials

### Issue: Routing Not Working

**Symptoms**:
- Requests return 404
- Routes not configured correctly

**Diagnosis**:
```bash
# Check dynamic configuration
cat /opt/traefik/dynamic.yml

# Check Traefik API for routes
curl http://localhost:8080/api/http/routers

# Test routing
curl -k -H "Host: aispector.exnada.com" https://localhost/health
```

**Solutions**:
1. **Route not configured**: Add route to dynamic.yml
2. **Host header mismatch**: Verify Host header matches route
3. **Configuration error**: Validate YAML syntax
4. **Reload Traefik**: Restart to pick up changes
   ```bash
   systemctl restart traefik
   ```

### Issue: HTTP Not Redirecting to HTTPS

**Symptoms**:
- HTTP requests not redirecting
- Mixed content warnings

**Diagnosis**:
```bash
# Test HTTP redirect
curl -I http://aispector.exnada.com/

# Check entrypoint configuration
cat /opt/traefik/traefik.yml | grep entryPoints
```

**Solutions**:
1. **Redirect middleware**: Verify redirect middleware is configured
2. **Entrypoint configuration**: Check entrypoint redirect settings
3. **Restart Traefik**: Apply configuration changes

## Diagnostic Commands

```bash
# Check Traefik status
systemctl status traefik
docker ps --filter name=traefik

# Test HTTPS endpoint
curl -k -H "Host: aispector.exnada.com" https://localhost/health

# Check Traefik logs
docker logs traefik | tail -100
journalctl -u traefik

# Verify configuration
cat /opt/traefik/traefik.yml
cat /opt/traefik/dynamic.yml

# Check backend connectivity
docker exec traefik wget -qO- http://vega.tailb821ac.ts.net:8000/health
```

## Log Locations

- **Container logs**: `docker logs traefik`
- **Systemd logs**: `journalctl -u traefik`
- **Configuration**: `/opt/traefik/traefik.yml`, `/opt/traefik/dynamic.yml`
- **Certificates**: `/opt/traefik/acme.json`
