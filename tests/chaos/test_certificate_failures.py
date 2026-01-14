#!/usr/bin/env python3
"""
Chaos engineering tests for certificate failures.
Tests behavior when certificates expire or fail to renew.
"""

import pytest
import ssl
import socket
from datetime import datetime, timedelta


class TestCertificateExpiration:
    """Test certificate expiration handling."""
    
    @pytest.mark.chaos
    def test_certificate_expiration_check(self, test_host):
        """Test that we can detect certificate expiration."""
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
                        
                        # Certificate should not be expired
                        assert days_until_expiry > 0, \
                            f"Certificate should not be expired (expires: {not_after})"
                        
                        # Warn if expiring soon
                        if days_until_expiry < 30:
                            pytest.warns(
                                UserWarning,
                                f"Certificate expires in {days_until_expiry} days"
                            )
        except Exception as e:
            pytest.fail(f"Certificate expiration check failed: {e}")


# Fixtures
@pytest.fixture
def test_host():
    """Get test host from environment or use default."""
    import os
    return os.getenv("TEST_HOST", "aispector.exnada.com")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-m", "chaos"])
