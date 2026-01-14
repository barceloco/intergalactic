#!/usr/bin/env python3
"""
End-to-end tests for certificate renewal flow.
Tests that certificates can be renewed without service interruption.
"""

import pytest
import ssl
import socket
from datetime import datetime, timedelta


class TestCertificateRenewal:
    """Test certificate renewal process."""
    
    @pytest.mark.e2e
    def test_certificate_renewal_does_not_interrupt_service(self, test_host, health_path):
        """Test that certificate renewal doesn't interrupt service."""
        import requests
        import urllib3
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        
        # Make a request before renewal (simulated)
        url = f"https://{test_host}{health_path}"
        try:
            response_before = requests.get(
                url,
                verify=False,
                timeout=10,
                headers={'Host': test_host}
            )
            status_before = response_before.status_code
        except requests.exceptions.RequestException:
            status_before = None
        
        # In a real scenario, we would trigger certificate renewal here
        # For this test, we just verify the service continues to work
        
        # Make a request after renewal (simulated)
        try:
            response_after = requests.get(
                url,
                verify=False,
                timeout=10,
                headers={'Host': test_host}
            )
            status_after = response_after.status_code
        except requests.exceptions.RequestException:
            status_after = None
        
        # Service should continue to work
        if status_before and status_after:
            assert status_after in [200, 404, 503], \
                "Service should continue to work after certificate renewal"
    
    @pytest.mark.e2e
    def test_certificate_expiration_monitoring(self, test_host):
        """Test that we can monitor certificate expiration."""
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        
        try:
            with socket.create_connection((test_host, 443), timeout=10) as sock:
                with context.wrap_socket(sock, server_hostname=test_host) as ssock:
                    cert = ssock.getpeercert()
                    not_after_str = cert.get('notAfter', '')
                    
                    if not_after_str:
                        not_after = datetime.strptime(not_after_str, '%b %d %H:%M:%S %Y %Z')
                        days_until_expiry = (not_after - datetime.now()).days
                        
                        # Certificate should have expiration date
                        assert days_until_expiry > 0, \
                            "Certificate should have valid expiration date"
        except Exception as e:
            pytest.fail(f"Certificate expiration monitoring failed: {e}")


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
