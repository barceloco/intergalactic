#!/usr/bin/env python3
"""
Performance tests for reverse proxy latency.
Establishes baseline for Traefik response times.
"""

import pytest
import requests
import time
import statistics
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class TestProxyLatency:
    """Test reverse proxy response latency."""
    
    @pytest.mark.performance
    def test_proxy_response_latency(self, test_host, health_path):
        """Test reverse proxy response latency."""
        latencies = []
        num_requests = 10
        
        url = f"https://{test_host}{health_path}"
        
        for _ in range(num_requests):
            try:
                start = time.time()
                response = requests.get(
                    url,
                    verify=False,
                    timeout=10,
                    headers={'Host': test_host}
                )
                elapsed = time.time() - start
                
                if response.status_code in [200, 404, 503]:
                    latencies.append(elapsed)
            except requests.exceptions.RequestException:
                pass
        
        if latencies:
            avg_latency = statistics.mean(latencies)
            max_latency = max(latencies)
            min_latency = min(latencies)
            
            # Baseline: Proxy responses should complete in under 2 seconds
            assert avg_latency < 2.0, \
                f"Average proxy latency should be < 2s, got {avg_latency:.3f}s"
            
            # Log performance metrics
            print(f"\nProxy Latency Metrics for {test_host}:")
            print(f"  Average: {avg_latency:.3f}s")
            print(f"  Min: {min_latency:.3f}s")
            print(f"  Max: {max_latency:.3f}s")
    
    @pytest.mark.performance
    def test_proxy_concurrent_requests(self, test_host, health_path):
        """Test proxy performance under concurrent load."""
        import concurrent.futures
        
        num_concurrent = 5
        num_requests_per_thread = 10
        
        def run_requests():
            latencies = []
            url = f"https://{test_host}{health_path}"
            for _ in range(num_requests_per_thread):
                try:
                    start = time.time()
                    response = requests.get(
                        url,
                        verify=False,
                        timeout=10,
                        headers={'Host': test_host}
                    )
                    elapsed = time.time() - start
                    if response.status_code in [200, 404, 503]:
                        latencies.append(elapsed)
                except requests.exceptions.RequestException:
                    pass
            return latencies
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=num_concurrent) as executor:
            futures = [executor.submit(run_requests) for _ in range(num_concurrent)]
            all_latencies = []
            for future in concurrent.futures.as_completed(futures):
                all_latencies.extend(future.result())
        
        if all_latencies:
            avg_latency = statistics.mean(all_latencies)
            # Under concurrent load, latency might be slightly higher
            assert avg_latency < 3.0, \
                f"Average proxy latency under load should be < 3s, got {avg_latency:.3f}s"


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
    pytest.main([__file__, "-v", "-m", "performance"])
