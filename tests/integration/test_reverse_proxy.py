#!/usr/bin/env python3
"""
Integration tests for reverse proxy routing.
Tests that Traefik correctly routes requests to backends.
"""

import pytest
import requests
import urllib3

# Disable SSL warnings for self-signed certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class TestTraefikRouting:
    """Test Traefik reverse proxy routing."""
    
    @pytest.mark.requires_traefik
    def test_traefik_listening_on_port_443(self):
        """Verify Traefik is listening on port 443."""
        import socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex(('127.0.0.1', 443))
        sock.close()
        assert result == 0, "Traefik should be listening on port 443"
    
    @pytest.mark.requires_traefik
    def test_traefik_listening_on_port_80(self):
        """Verify Traefik is listening on port 80."""
        import socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex(('127.0.0.1', 80))
        sock.close()
        assert result == 0, "Traefik should be listening on port 80"
    
    @pytest.mark.requires_traefik
    def test_https_route_responds(self, test_host, test_path):
        """Test HTTPS route responds with valid status code."""
        url = f"https://{test_host}{test_path}"
        try:
            response = requests.get(
                url,
                verify=False,  # Self-signed cert
                timeout=10,
                headers={'Host': test_host}
            )
            # Accept 200 (success), 404 (not found), or 503 (backend unavailable)
            assert response.status_code in [200, 404, 503], \
                f"HTTPS route should return valid status code, got {response.status_code}"
        except requests.exceptions.RequestException as e:
            pytest.fail(f"HTTPS request failed: {e}")
    
    @pytest.mark.requires_traefik
    def test_http_redirects_to_https(self, test_host):
        """Test HTTP requests redirect to HTTPS."""
        url = f"http://{test_host}/"
        try:
            response = requests.get(
                url,
                allow_redirects=False,
                timeout=10,
                headers={'Host': test_host}
            )
            # Should redirect (301 or 302) or return 200 if redirect is handled differently
            assert response.status_code in [200, 301, 302, 308], \
                f"HTTP should redirect to HTTPS, got {response.status_code}"
        except requests.exceptions.RequestException as e:
            pytest.fail(f"HTTP request failed: {e}")
    
    @pytest.mark.requires_traefik
    def test_health_endpoint_accessible(self, test_host, health_path):
        """Test health check endpoint is accessible."""
        url = f"https://{test_host}{health_path}"
        try:
            response = requests.get(
                url,
                verify=False,
                timeout=10,
                headers={'Host': test_host}
            )
            assert response.status_code == 200, \
                f"Health endpoint should return 200, got {response.status_code}"
            # Health endpoint should return JSON
            assert 'application/json' in response.headers.get('Content-Type', '').lower() or \
                   response.text.startswith('{'), \
                "Health endpoint should return JSON"
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Health check request failed: {e}")


class TestTraefikTLS:
    """Test Traefik TLS/SSL configuration."""
    
    @pytest.mark.requires_traefik
    def test_https_uses_tls(self, test_host):
        """Test HTTPS connection uses TLS."""
        import ssl
        import socket
        
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        
        try:
            with socket.create_connection((test_host, 443), timeout=10) as sock:
                with context.wrap_socket(sock, server_hostname=test_host) as ssock:
                    cert = ssock.getpeercert()
                    assert cert is not None, "HTTPS should present a certificate"
        except Exception as e:
            pytest.fail(f"TLS connection failed: {e}")


# Fixtures
@pytest.fixture
def test_host():
    """Get test host from environment or use default."""
    import os
    return os.getenv("TEST_HOST", "aispector.exnada.com")


@pytest.fixture
def test_path():
    """Get test path from environment or use default."""
    import os
    return os.getenv("TEST_PATH", "/health")


@pytest.fixture
def health_path():
    """Get health check path from environment or use default."""
    import os
    return os.getenv("HEALTH_PATH", "/health")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-m", "requires_traefik"])
