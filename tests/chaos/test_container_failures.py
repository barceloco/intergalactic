#!/usr/bin/env python3
"""
Chaos engineering tests for container failure scenarios.
Tests recovery mechanisms when containers crash.
"""

import pytest
import subprocess
import time
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class TestCoreDNSContainerFailure:
    """Test CoreDNS container failure and recovery."""
    
    @pytest.mark.chaos
    def test_coredns_container_stop_and_recover(self):
        """Test that CoreDNS recovers after container stop."""
        # Stop container
        subprocess.run(['docker', 'stop', 'coredns'], check=False)
        time.sleep(2)
        
        # Verify container is stopped
        result = subprocess.run(
            ['docker', 'ps', '--filter', 'name=coredns', '--format', '{{.Names}}'],
            capture_output=True,
            text=True
        )
        assert 'coredns' not in result.stdout, "Container should be stopped"
        
        # Wait for systemd to restart (should happen within 10 seconds)
        max_wait = 10
        wait_interval = 1
        elapsed = 0
        
        while elapsed < max_wait:
            result = subprocess.run(
                ['docker', 'ps', '--filter', 'name=coredns', '--format', '{{.Names}}'],
                capture_output=True,
                text=True
            )
            if 'coredns' in result.stdout:
                break
            time.sleep(wait_interval)
            elapsed += wait_interval
        
        assert 'coredns' in result.stdout, \
            f"CoreDNS container should restart within {max_wait} seconds"
    
    @pytest.mark.chaos
    def test_coredns_container_kill_and_recover(self):
        """Test that CoreDNS recovers after container is killed."""
        # Kill container
        subprocess.run(['docker', 'kill', 'coredns'], check=False)
        time.sleep(2)
        
        # Wait for systemd to restart
        max_wait = 10
        wait_interval = 1
        elapsed = 0
        
        while elapsed < max_wait:
            result = subprocess.run(
                ['docker', 'ps', '--filter', 'name=coredns', '--format', '{{.Names}}'],
                capture_output=True,
                text=True
            )
            if 'coredns' in result.stdout:
                break
            time.sleep(wait_interval)
            elapsed += wait_interval
        
        assert 'coredns' in result.stdout, \
            f"CoreDNS container should restart within {max_wait} seconds"


class TestTraefikContainerFailure:
    """Test Traefik container failure and recovery."""
    
    @pytest.mark.chaos
    def test_traefik_container_stop_and_recover(self):
        """Test that Traefik recovers after container stop."""
        # Stop container
        subprocess.run(['docker', 'stop', 'traefik'], check=False)
        time.sleep(2)
        
        # Verify container is stopped
        result = subprocess.run(
            ['docker', 'ps', '--filter', 'name=traefik', '--format', '{{.Names}}'],
            capture_output=True,
            text=True
        )
        assert 'traefik' not in result.stdout, "Container should be stopped"
        
        # Wait for systemd to restart
        max_wait = 10
        wait_interval = 1
        elapsed = 0
        
        while elapsed < max_wait:
            result = subprocess.run(
                ['docker', 'ps', '--filter', 'name=traefik', '--format', '{{.Names}}'],
                capture_output=True,
                text=True
            )
            if 'traefik' in result.stdout:
                break
            time.sleep(wait_interval)
            elapsed += wait_interval
        
        assert 'traefik' in result.stdout, \
            f"Traefik container should restart within {max_wait} seconds"
    
    @pytest.mark.chaos
    def test_traefik_recovery_restores_routing(self, test_host, health_path):
        """Test that Traefik routing is restored after recovery."""
        # Stop container
        subprocess.run(['docker', 'stop', 'traefik'], check=False)
        time.sleep(2)
        
        # Wait for restart
        max_wait = 15
        wait_interval = 1
        elapsed = 0
        
        while elapsed < max_wait:
            result = subprocess.run(
                ['docker', 'ps', '--filter', 'name=traefik', '--format', '{{.Names}}'],
                capture_output=True,
                text=True
            )
            if 'traefik' in result.stdout:
                # Give it a moment to fully start
                time.sleep(2)
                break
            time.sleep(wait_interval)
            elapsed += wait_interval
        
        # Test routing is working
        url = f"https://{test_host}{health_path}"
        try:
            response = requests.get(
                url,
                verify=False,
                timeout=10,
                headers={'Host': test_host}
            )
            # Accept 200, 404, or 503 (backend might not be ready)
            assert response.status_code in [200, 404, 503], \
                f"Routing should work after recovery, got {response.status_code}"
        except requests.exceptions.RequestException:
            pytest.fail("Routing should be restored after recovery")


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
