"""
Pytest configuration for Testinfra tests.
This file sets up test fixtures and configuration.
"""

import pytest


def pytest_configure(config):
    """Configure pytest for Testinfra."""
    # Add custom markers
    config.addinivalue_line(
        "markers", "requires_docker: mark test as requiring Docker"
    )
    config.addinivalue_line(
        "markers", "requires_tailscale: mark test as requiring Tailscale"
    )
    config.addinivalue_line(
        "markers", "requires_firewall: mark test as requiring firewall_nftables role"
    )


@pytest.fixture(scope="session")
def ansible_inventory():
    """Return path to Ansible inventory file."""
    import os
    inventory_path = os.path.join(
        os.path.dirname(__file__),
        "../../ansible/inventories/prod/hosts.yml"
    )
    return inventory_path
