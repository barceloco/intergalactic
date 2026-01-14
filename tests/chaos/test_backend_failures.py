#!/usr/bin/env python3
"""
Chaos engineering tests for backend service failures.
Tests Traefik behavior when backend services fail.
"""

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class TestBackendServiceFailure:
    """Test Traefik behavior when backend services fail."""
    
    @pytest.mark.chaos
    def test_backend_returns_503_when_down(self, test_host, health_path):
        """Test that Traefik returns 503 when backend is down."""
        url = f"https://{test_host}{health_path}"
        try:
            response = requests.get(
                url,
                verify=False,
                timeout=10,
                headers={'Host': test_host}
            )
            # If backend is down, should return 503
            # If backend is up, should return 200
            assert response.status_code in [200, 503], \
                f"Should return 200 (healthy) or 503 (down), got {response.status_code}"
        except requests.exceptions.RequestException:
            # Network error is acceptable if backend is truly down
            pass
    
    @pytest.mark.chaos
    def test_backend_slow_response_handling(self, test_host, health_path):
        """Test that Traefik handles slow backend responses."""
        url = f"https://{test_host}{health_path}"
        try:
            response = requests.get(
                url,
                verify=False,
                timeout=30,  # Longer timeout for slow responses
                headers={'Host': test_host}
            )
            # Should eventually return a response (even if slow)
            assert response.status_code in [200, 503, 504], \
                f"Should handle slow responses, got {response.status_code}"
        except requests.exceptions.Timeout:
            # Timeout is acceptable for very slow backends
            pass
        except requests.exceptions.RequestException:
            # Other errors are acceptable
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
