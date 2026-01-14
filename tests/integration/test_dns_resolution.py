#!/usr/bin/env python3
"""
Integration tests for DNS resolution.
Tests that CoreDNS correctly resolves internal and external domains.
"""

import pytest
import subprocess
import socket


class TestInternalDNSResolution:
    """Test internal DNS resolution via CoreDNS."""
    
    @pytest.mark.requires_coredns
    def test_coredns_listening_on_port_53(self):
        """Verify CoreDNS is listening on port 53."""
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        result = sock.connect_ex(('127.0.0.1', 53))
        sock.close()
        assert result == 0, "CoreDNS should be listening on port 53"
    
    @pytest.mark.requires_coredns
    def test_resolve_internal_domain(self, internal_domain):
        """Test DNS resolution of internal domain."""
        try:
            result = subprocess.run(
                ['dig', '@127.0.0.1', '+timeout=5', '+tries=2', internal_domain],
                capture_output=True,
                text=True,
                timeout=10
            )
            assert result.returncode == 0, f"DNS resolution failed: {result.stderr}"
            assert "NOERROR" in result.stdout, "DNS query should return NOERROR"
        except FileNotFoundError:
            pytest.skip("dig command not available")
    
    @pytest.mark.requires_coredns
    def test_resolve_internal_host(self, internal_host, internal_domain):
        """Test DNS resolution of internal host."""
        fqdn = f"{internal_host}.{internal_domain}"
        try:
            result = subprocess.run(
                ['dig', '@127.0.0.1', '+timeout=5', '+tries=2', fqdn],
                capture_output=True,
                text=True,
                timeout=10
            )
            assert result.returncode == 0, f"DNS resolution failed: {result.stderr}"
            assert "NOERROR" in result.stdout, f"DNS query for {fqdn} should return NOERROR"
        except FileNotFoundError:
            pytest.skip("dig command not available")
    
    @pytest.mark.requires_coredns
    def test_dns_returns_a_record(self, internal_host, internal_domain):
        """Test DNS returns A record with IP address."""
        fqdn = f"{internal_host}.{internal_domain}"
        try:
            result = subprocess.run(
                ['dig', '@127.0.0.1', '+short', fqdn],
                capture_output=True,
                text=True,
                timeout=10
            )
            assert result.returncode == 0, f"DNS resolution failed: {result.stderr}"
            # Should return at least one IP address
            ip_addresses = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
            assert len(ip_addresses) > 0, f"DNS should return at least one A record for {fqdn}"
            # Verify it's a valid IP address format
            import re
            ip_pattern = r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
            assert any(re.match(ip_pattern, ip) for ip in ip_addresses), \
                f"DNS should return valid IP address for {fqdn}"
        except FileNotFoundError:
            pytest.skip("dig command not available")


class TestExternalDNSForwarding:
    """Test that CoreDNS forwards external queries correctly."""
    
    @pytest.mark.requires_coredns
    def test_forward_external_domain(self):
        """Test DNS forwarding for external domain."""
        external_domain = "google.com"
        try:
            result = subprocess.run(
                ['dig', '@127.0.0.1', '+timeout=5', '+tries=2', external_domain],
                capture_output=True,
                text=True,
                timeout=10
            )
            assert result.returncode == 0, f"DNS forwarding failed: {result.stderr}"
            assert "NOERROR" in result.stdout, "DNS forwarding should return NOERROR"
        except FileNotFoundError:
            pytest.skip("dig command not available")


# Fixtures
@pytest.fixture
def internal_domain():
    """Get internal domain from environment or use default."""
    import os
    return os.getenv("INTERNAL_DNS_DOMAIN", "exnada.com")


@pytest.fixture
def internal_host():
    """Get internal host from environment or use default."""
    import os
    return os.getenv("INTERNAL_DNS_HOST", "mpnas")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-m", "requires_coredns"])
