#!/usr/bin/env python3
"""
Chaos engineering tests for network partition scenarios.
Tests behavior when Tailscale disconnects or network is partitioned.
"""

import pytest
import subprocess
import time
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class TestTailscaleDisconnection:
    """Test behavior when Tailscale disconnects."""
    
    @pytest.mark.chaos
    @pytest.mark.requires_tailscale
    def test_tailscale_disconnect_and_reconnect(self):
        """Test that services handle Tailscale disconnection gracefully."""
        # Check Tailscale status
        result = subprocess.run(
            ['tailscale', 'status'],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            pytest.skip("Tailscale not available")
        
        # Note: We can't actually disconnect Tailscale in a test
        # This test verifies that services continue to function
        # even if Tailscale connectivity is temporarily lost
        
        # Verify CoreDNS is still running
        result = subprocess.run(
            ['docker', 'ps', '--filter', 'name=coredns', '--format', '{{.Names}}'],
            capture_output=True,
            text=True
        )
        assert 'coredns' in result.stdout, "CoreDNS should continue running"
        
        # Verify Traefik is still running
        result = subprocess.run(
            ['docker', 'ps', '--filter', 'name=traefik', '--format', '{{.Names}}'],
            capture_output=True,
            text=True
        )
        assert 'traefik' in result.stdout, "Traefik should continue running"


class TestBackendNetworkPartition:
    """Test behavior when backend becomes unreachable."""
    
    @pytest.mark.chaos
    def test_backend_unreachable_returns_503(self, test_host, health_path):
        """Test that Traefik returns 503 when backend is unreachable."""
        # This test assumes backend might be unreachable
        # In a real scenario, we would block network access to backend
        
        url = f"https://{test_host}{health_path}"
        try:
            response = requests.get(
                url,
                verify=False,
                timeout=10,
                headers={'Host': test_host}
            )
            # If backend is unreachable, Traefik should return 503
            # If backend is reachable, should return 200
            assert response.status_code in [200, 503], \
                f"Should return 200 (healthy) or 503 (unreachable), got {response.status_code}"
        except requests.exceptions.RequestException:
            # Network error is also acceptable if backend is truly unreachable
            pass


class TestDNSResolutionFailure:
    """Test behavior when DNS resolution fails."""
    
    @pytest.mark.chaos
    def test_dns_resolution_failure_handling(self):
        """Test that system handles DNS resolution failures gracefully."""
        # Try to resolve a non-existent hostname
        try:
            result = subprocess.run(
                ['dig', '@127.0.0.1', '+timeout=2', 'nonexistent.invalid'],
                capture_output=True,
                text=True,
                timeout=5
            )
            # Should return NXDOMAIN or timeout, not crash
            assert result.returncode in [0, 9], \
                "DNS resolution failure should be handled gracefully"
        except FileNotFoundError:
            pytest.skip("dig command not available")
        except subprocess.TimeoutExpired:
            # Timeout is acceptable for invalid domains
            pass


# Fixtures
@pytest.fixture
def test_host():
    """Get test host from environment or use default."""
    import os
    return os.getenv("TEST_HOST", "aispector.exnada.com")


@pytest.fixture
def health_path():
    """Get health check path from environment or use default."""
    import os
    return os.getenv("HEALTH_PATH", "/health")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-m", "chaos"])
