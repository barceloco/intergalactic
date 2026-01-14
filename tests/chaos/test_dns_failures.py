#!/usr/bin/env python3
"""
Chaos engineering tests for DNS service failures.
Tests recovery when DNS service fails.
"""

import pytest
import subprocess
import time


class TestDNSFailureRecovery:
    """Test DNS service failure and recovery."""
    
    @pytest.mark.chaos
    def test_coredns_stop_dns_unavailable(self):
        """Test that DNS becomes unavailable when CoreDNS stops."""
        # Stop CoreDNS
        subprocess.run(['docker', 'stop', 'coredns'], check=False)
        time.sleep(2)
        
        # Try DNS query
        try:
            result = subprocess.run(
                ['dig', '@127.0.0.1', '+timeout=2', 'exnada.com'],
                capture_output=True,
                text=True,
                timeout=5
            )
            # DNS should fail or timeout
            assert result.returncode != 0 or 'SERVFAIL' in result.stdout or \
                   'timeout' in result.stdout.lower(), \
                "DNS should fail when CoreDNS is stopped"
        except FileNotFoundError:
            pytest.skip("dig command not available")
        except subprocess.TimeoutExpired:
            # Timeout is acceptable when DNS is down
            pass
    
    @pytest.mark.chaos
    def test_coredns_restart_dns_available(self):
        """Test that DNS becomes available when CoreDNS restarts."""
        # Ensure CoreDNS is running
        subprocess.run(['docker', 'start', 'coredns'], check=False)
        time.sleep(5)  # Give it time to start
        
        # Try DNS query
        try:
            result = subprocess.run(
                ['dig', '@127.0.0.1', '+timeout=5', 'exnada.com'],
                capture_output=True,
                text=True,
                timeout=10
            )
            # DNS should work
            assert result.returncode == 0, \
                f"DNS should work when CoreDNS is running: {result.stderr}"
            assert 'NOERROR' in result.stdout, \
                "DNS should return NOERROR when CoreDNS is running"
        except FileNotFoundError:
            pytest.skip("dig command not available")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-m", "chaos"])
