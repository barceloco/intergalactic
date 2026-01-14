# Integration Tests

Integration tests verify that multiple components work together correctly on actual deployed systems.

## DNS Resolution Tests

Tests CoreDNS split-horizon DNS functionality:
- Internal domain resolution (private hosts)
- External domain forwarding (public DNS)
- A record returns
- Service availability

### Running DNS Tests

**Prerequisites:**
- CoreDNS deployed and running on target host
- SSH access to target host
- `dig` command available (install `dnsutils` package)

**Run on deployed host:**

```bash
# SSH to host with CoreDNS
ssh ansible@rigel

# Run DNS integration tests
cd /path/to/intergalactic
python3 tests/integration/test_dns_resolution.py
```

**With custom configuration:**

```bash
# Set environment variables
export INTERNAL_DNS_DOMAIN="exnada.com"
export INTERNAL_DNS_HOST="mpnas"

# Run tests
python3 tests/integration/test_dns_resolution.py
```

**With pytest:**

```bash
# Run with pytest
pytest tests/integration/test_dns_resolution.py -v -m requires_coredns

# Run specific test
pytest tests/integration/test_dns_resolution.py::TestInternalDNSResolution::test_coredns_listening_on_port_53 -v
```

## Backend Connectivity Tests

Tests that Traefik can connect to backend services.

**Status:** Skeleton only (implementation needed)

## Reverse Proxy Tests

Tests that Traefik correctly routes HTTP requests to backends.

**Status:** Skeleton only (implementation needed)

## TLS Certificate Tests

Tests that certificates are valid and properly configured.

**Status:** Skeleton only (implementation needed)

## Running All Integration Tests

```bash
# Run all integration tests
pytest tests/integration/ -v

# Run only tests that require specific services
pytest tests/integration/ -v -m requires_coredns
pytest tests/integration/ -v -m requires_traefik
```

## Adding New Integration Tests

1. Create new test file: `test_<feature>.py`
2. Use pytest fixtures for configuration
3. Mark tests with service requirements: `@pytest.mark.requires_<service>`
4. Provide clear error messages when services are unavailable
5. Document prerequisites and setup in this README

## Integration Test Philosophy

Integration tests should:
- Run on actual deployed systems (not mocked)
- Test interactions between components
- Verify end-to-end functionality
- Be safe to run repeatedly (idempotent)
- Provide clear diagnostics when they fail

Integration tests should NOT:
- Make destructive changes
- Require manual cleanup
- Depend on external services (unless testing external integrations)
- Duplicate unit test coverage
