"""
Testinfra tests for Tailscale configuration.
These tests verify Tailscale is installed and connected.
"""


def test_tailscale_installed(host):
    """Verify Tailscale is installed."""
    # Tailscale can be installed via different methods
    # Check if tailscale command exists
    tailscale_cmd = host.run("which tailscale")
    assert tailscale_cmd.rc == 0, "tailscale command not found"


def test_tailscale_service_running(host):
    """Verify Tailscale service is running."""
    tailscale_service = host.service("tailscaled")
    assert tailscale_service.is_running
    assert tailscale_service.is_enabled


def test_tailscale_connected(host):
    """Verify Tailscale is connected to tailnet."""
    # Check tailscale status
    result = host.run("tailscale status --json")
    assert result.rc == 0, "tailscale status failed"
    
    # Basic check - if status returns JSON, Tailscale is likely working
    assert len(result.stdout) > 0


def test_tailscale_interface_exists(host):
    """Verify Tailscale interface (tailscale0) exists."""
    result = host.run("ip addr show tailscale0")
    assert result.rc == 0, "tailscale0 interface not found"


def test_tailscale_ip_assigned(host):
    """Verify Tailscale has an IP address assigned."""
    result = host.run("tailscale ip -4")
    assert result.rc == 0, "tailscale IP detection failed"
    # Should return an IP address (100.x.x.x format)
    assert result.stdout.strip().startswith("100.")
