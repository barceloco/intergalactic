# Testinfra Tests

This directory contains Testinfra tests for verifying server state after Ansible deployment.

## What is Testinfra?

Testinfra is a pytest plugin that allows you to write unit tests for server configuration. It can test against:
- SSH hosts
- Docker containers
- Ansible inventory
- Local system

## Installation

Install Testinfra and dependencies:

```bash
pip install -r ansible/requirements-dev.txt
```

Or install individually:

```bash
pip install testinfra pytest
```

## Running Tests

### Test Against Ansible Inventory

Test all hosts in production inventory:

```bash
pytest tests/testinfra/ \
  --hosts=ansible://all \
  --ansible-inventory=ansible/inventories/prod/hosts.yml \
  -v
```

### Test Specific Host

Test a single host:

```bash
pytest tests/testinfra/ \
  --hosts=ansible://rigel \
  --ansible-inventory=ansible/inventories/prod/hosts.yml \
  -v
```

### Test Specific Test File

Run only common system tests:

```bash
pytest tests/testinfra/test_common.py \
  --hosts=ansible://rigel \
  --ansible-inventory=ansible/inventories/prod/hosts.yml \
  -v
```

### Test with Markers

Run only tests that require Docker:

```bash
pytest tests/testinfra/ \
  --hosts=ansible://rigel \
  --ansible-inventory=ansible/inventories/prod/hosts.yml \
  -m requires_docker \
  -v
```

## Test Files

- `test_common.py` - Common system configuration (ansible user, SSH, hostname)
- `test_docker.py` - Docker installation and configuration
- `test_firewall.py` - nftables firewall configuration
- `test_tailscale.py` - Tailscale installation and connectivity

## Writing New Tests

Create a new test file following this pattern:

```python
"""Testinfra tests for [feature]."""

def test_feature_exists(host):
    """Verify feature is installed/configured."""
    # Use host.package(), host.service(), host.file(), etc.
    feature = host.package("feature-package")
    assert feature.is_installed
```

## Test Structure

Tests are organized by feature/role:
- Each test file focuses on one area
- Tests are independent and can run in any order
- Tests use descriptive names that explain what they verify

## Integration with CI/CD

Add to your CI/CD pipeline:

```yaml
- name: Run Testinfra tests
  run: |
    pytest tests/testinfra/ \
      --hosts=ansible://all \
      --ansible-inventory=ansible/inventories/prod/hosts.yml \
      -v
```

## Troubleshooting

### Connection Issues

If tests fail to connect:
1. Verify SSH keys are configured
2. Check Ansible inventory is correct
3. Ensure hosts are reachable

### Test Failures

If tests fail:
1. Check the error message for details
2. Verify the role was actually applied
3. Check server state manually

### Slow Tests

Testinfra tests can be slow if:
- Network latency is high
- Many hosts are tested
- Tests perform slow operations

Use markers to skip slow tests or test fewer hosts.
