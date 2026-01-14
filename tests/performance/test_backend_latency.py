#!/usr/bin/env python3
"""
Performance tests for backend response latency.
Establishes baseline for backend service response times.
"""

import pytest
import requests
import time
import statistics
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class TestBackendLatency:
    """Test backend service response latency."""
    
    @pytest.mark.performance
    def test_backend_response_latency(self, backend_url, health_path):
        """Test backend direct response latency."""
        latencies = []
        num_requests = 10
        
        full_url = f"{backend_url}{health_path}"
        
        for _ in range(num_requests):
            try:
                start = time.time()
                response = requests.get(full_url, timeout=10, verify=False)
                elapsed = time.time() - start
                
                if response.status_code == 200:
                    latencies.append(elapsed)
            except requests.exceptions.RequestException:
                pass
        
        if latencies:
            avg_latency = statistics.mean(latencies)
            max_latency = max(latencies)
            min_latency = min(latencies)
            
            # Baseline: Backend responses should complete in under 1 second
            assert avg_latency < 1.0, \
                f"Average backend latency should be < 1s, got {avg_latency:.3f}s"
            
            # Log performance metrics
            print(f"\nBackend Latency Metrics for {backend_url}:")
            print(f"  Average: {avg_latency:.3f}s")
            print(f"  Min: {min_latency:.3f}s")
            print(f"  Max: {max_latency:.3f}s")


# Fixtures
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
    pytest.main([__file__, "-v", "-m", "performance"])
