#!/usr/bin/env python3
"""
Integration tests for backend connectivity.
Tests that Traefik can reach backend services.
"""

import pytest
import requests
import subprocess
import socket
import urllib3

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class TestBackendReachability:
    """Test that backends are reachable from Traefik."""
    
    @pytest.mark.requires_traefik
    def test_backend_resolvable_from_traefik(self, backend_host):
        """Test backend hostname is resolvable from Traefik container."""
        try:
            result = subprocess.run(
                ['docker', 'exec', 'traefik', 'getent', 'hosts', backend_host],
                capture_output=True,
                text=True,
                timeout=10
            )
            # getent hosts returns 0 if found, non-zero if not found
            assert result.returncode == 0, \
                f"Backend {backend_host} should be resolvable from Traefik: {result.stderr}"
        except FileNotFoundError:
            pytest.skip("docker command not available")
        except subprocess.TimeoutExpired:
            pytest.fail("Backend resolution timed out")
    
    @pytest.mark.requires_traefik
    def test_backend_reachable_from_traefik(self, backend_url, health_path):
        """Test backend is reachable from Traefik container."""
        full_url = f"{backend_url}{health_path}"
        try:
            result = subprocess.run(
                ['docker', 'exec', 'traefik', 'wget', '-qO-', '--timeout=5', full_url],
                capture_output=True,
                text=True,
                timeout=10
            )
            # wget returns 0 on success
            assert result.returncode == 0, \
                f"Backend {full_url} should be reachable from Traefik: {result.stderr}"
        except FileNotFoundError:
            pytest.skip("docker command not available")
        except subprocess.TimeoutExpired:
            pytest.fail("Backend connectivity test timed out")
    
    @pytest.mark.requires_backend
    def test_backend_directly_accessible(self, backend_url, health_path):
        """Test backend is directly accessible (not through Traefik)."""
        full_url = f"{backend_url}{health_path}"
        try:
            response = requests.get(full_url, timeout=10, verify=False)
            assert response.status_code == 200, \
                f"Backend should return 200, got {response.status_code}"
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Backend direct access failed: {e}")


class TestBackendHealth:
    """Test backend health endpoints."""
    
    @pytest.mark.requires_backend
    def test_backend_health_endpoint(self, backend_url, health_path):
        """Test backend health endpoint returns healthy status."""
        full_url = f"{backend_url}{health_path}"
        try:
            response = requests.get(full_url, timeout=10, verify=False)
            assert response.status_code == 200, \
                f"Health endpoint should return 200, got {response.status_code}"
            
            # Try to parse as JSON
            try:
                data = response.json()
                # Check for common health check fields
                assert 'status' in data or 'healthy' in str(data).lower() or \
                       'version' in data, \
                    "Health endpoint should return status information"
            except ValueError:
                # Not JSON, but that's okay
                pass
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Backend health check failed: {e}")


# Fixtures
@pytest.fixture
def backend_host():
    """Get backend host from environment or use default."""
    import os
    return os.getenv("BACKEND_HOST", "vega.tailb821ac.ts.net")


@pytest.fixture
def backend_url():
    """Get backend URL from environment or use default."""
    import os
    return os.getenv("BACKEND_URL", "http://vega.tailb821ac.ts.net:8000")


@pytest.fixture
def health_path():
    """Get health check path from environment or use default."""
    import os
    return os.getenv("HEALTH_PATH", "/health")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
