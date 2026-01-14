"""
Testinfra tests for firewall configuration.
These tests verify nftables firewall is configured correctly.
"""


def test_nftables_installed(host):
    """Verify nftables is installed."""
    nftables_pkg = host.package("nftables")
    assert nftables_pkg.is_installed


def test_nftables_service_running(host):
    """Verify nftables service is running."""
    nftables_service = host.service("nftables")
    assert nftables_service.is_running
    assert nftables_service.is_enabled


def test_nftables_config_exists(host):
    """Verify nftables configuration file exists."""
    nftables_config = host.file("/etc/nftables.conf")
    assert nftables_config.exists
    assert nftables_config.is_file


def test_nftables_config_valid(host):
    """Verify nftables configuration is valid."""
    # Check syntax of nftables config
    result = host.run("nft -c -f /etc/nftables.conf")
    assert result.rc == 0, f"nftables config syntax error: {result.stderr}"


def test_ssh_port_allowed(host):
    """Verify SSH port is allowed in firewall."""
    # Check if SSH port (22) is in the ruleset
    result = host.run("nft list ruleset | grep -E 'tcp dport.*22.*accept'")
    # This should find at least one rule allowing SSH
    assert result.rc == 0 or "tcp dport 22 accept" in result.stdout
