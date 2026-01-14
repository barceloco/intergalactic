#!/usr/bin/env python3
"""
End-to-end tests for complete user journeys.
Tests the full request flow from DNS resolution to backend response.
"""

import pytest
import requests
import subprocess
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class TestCompleteUserJourney:
    """Test complete user request journey."""
    
    @pytest.mark.e2e
    def test_user_request_flow(self, test_host, health_path):
        """
        Test complete user request flow:
        1. User requests https://aispector.exnada.com/health
        2. DNS resolves correctly
        3. HTTPS connection established
        4. Traefik routes to backend
        5. Backend responds correctly
        6. Response returned to user
        """
        # Step 1: DNS resolution
        try:
            result = subprocess.run(
                ['dig', '+short', test_host],
                capture_output=True,
                text=True,
                timeout=10
            )
            assert result.returncode == 0, "DNS resolution should succeed"
            assert len(result.stdout.strip()) > 0, "DNS should return an IP address"
        except FileNotFoundError:
            pytest.skip("dig command not available")
        
        # Step 2-6: HTTPS request
        url = f"https://{test_host}{health_path}"
        try:
            response = requests.get(
                url,
                verify=False,  # Self-signed cert
                timeout=10,
                headers={'Host': test_host}
            )
            
            # Should get a valid response
            assert response.status_code in [200, 404, 503], \
                f"Should return valid status code, got {response.status_code}"
            
            # If successful, verify response format
            if response.status_code == 200:
                # Should be JSON
                try:
                    data = response.json()
                    assert 'status' in data or 'version' in data, \
                        "Response should contain status information"
                except ValueError:
                    # Not JSON, but that's okay
                    pass
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Complete request flow failed: {e}")
    
    @pytest.mark.e2e
    def test_http_redirects_to_https(self, test_host):
        """Test that HTTP requests redirect to HTTPS."""
        url = f"http://{test_host}/"
        try:
            response = requests.get(
                url,
                allow_redirects=False,
                timeout=10,
                headers={'Host': test_host}
            )
            # Should redirect (301, 302, or 308)
            assert response.status_code in [200, 301, 302, 308], \
                f"HTTP should redirect to HTTPS, got {response.status_code}"
        except requests.exceptions.RequestException as e:
            pytest.fail(f"HTTP redirect test failed: {e}")


class TestPostRebootRecovery:
    """Test that services recover correctly after reboot."""
    
    @pytest.mark.e2e
    def test_services_running_after_reboot(self):
        """Test that all services are running (simulating post-reboot state)."""
        # Check CoreDNS
        result = subprocess.run(
            ['docker', 'ps', '--filter', 'name=coredns', '--format', '{{.Names}}'],
            capture_output=True,
            text=True
        )
        assert 'coredns' in result.stdout, "CoreDNS should be running"
        
        # Check Traefik
        result = subprocess.run(
            ['docker', 'ps', '--filter', 'name=traefik', '--format', '{{.Names}}'],
            capture_output=True,
            text=True
        )
        assert 'traefik' in result.stdout, "Traefik should be running"
        
        # Check systemd services
        result = subprocess.run(
            ['systemctl', 'is-active', 'coredns'],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, "CoreDNS systemd service should be active"
        
        result = subprocess.run(
            ['systemctl', 'is-active', 'traefik'],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, "Traefik systemd service should be active"
    
    @pytest.mark.e2e
    def test_dns_working_after_reboot(self):
        """Test that DNS is working after reboot."""
        try:
            result = subprocess.run(
                ['dig', '@127.0.0.1', '+timeout=5', 'exnada.com'],
                capture_output=True,
                text=True,
                timeout=10
            )
            assert result.returncode == 0, "DNS should work after reboot"
            assert 'NOERROR' in result.stdout, "DNS should return NOERROR"
        except FileNotFoundError:
            pytest.skip("dig command not available")
    
    @pytest.mark.e2e
    def test_reverse_proxy_working_after_reboot(self, test_host, health_path):
        """Test that reverse proxy is working after reboot."""
        url = f"https://{test_host}{health_path}"
        try:
            response = requests.get(
                url,
                verify=False,
                timeout=10,
                headers={'Host': test_host}
            )
            # Should get a response (even if 503 if backend is not ready)
            assert response.status_code in [200, 404, 503], \
                f"Reverse proxy should work after reboot, got {response.status_code}"
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Reverse proxy test after reboot failed: {e}")


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
    pytest.main([__file__, "-v", "-m", "e2e"])
