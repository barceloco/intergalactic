#!/usr/bin/env python3
"""
Performance tests for DNS latency.
Establishes baseline for DNS response times.
"""

import pytest
import subprocess
import time
import statistics


class TestDNSLatency:
    """Test DNS query latency."""
    
    @pytest.mark.performance
    def test_dns_query_latency(self, internal_domain):
        """Test DNS query latency for internal domain."""
        latencies = []
        num_queries = 10
        
        try:
            for _ in range(num_queries):
                start = time.time()
                result = subprocess.run(
                    ['dig', '@127.0.0.1', '+timeout=5', internal_domain],
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                elapsed = time.time() - start
                
                if result.returncode == 0:
                    latencies.append(elapsed)
            
            if latencies:
                avg_latency = statistics.mean(latencies)
                max_latency = max(latencies)
                min_latency = min(latencies)
                
                # Baseline: DNS queries should complete in under 1 second
                assert avg_latency < 1.0, \
                    f"Average DNS latency should be < 1s, got {avg_latency:.3f}s"
                
                # Log performance metrics
                print(f"\nDNS Latency Metrics for {internal_domain}:")
                print(f"  Average: {avg_latency:.3f}s")
                print(f"  Min: {min_latency:.3f}s")
                print(f"  Max: {max_latency:.3f}s")
        except FileNotFoundError:
            pytest.skip("dig command not available")
    
    @pytest.mark.performance
    def test_dns_concurrent_queries(self, internal_domain):
        """Test DNS performance under concurrent load."""
        import concurrent.futures
        
        num_concurrent = 5
        num_queries_per_thread = 10
        
        def run_queries():
            latencies = []
            try:
                for _ in range(num_queries_per_thread):
                    start = time.time()
                    result = subprocess.run(
                        ['dig', '@127.0.0.1', '+timeout=5', internal_domain],
                        capture_output=True,
                        text=True,
                        timeout=10
                    )
                    elapsed = time.time() - start
                    if result.returncode == 0:
                        latencies.append(elapsed)
            except Exception:
                pass
            return latencies
        
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=num_concurrent) as executor:
                futures = [executor.submit(run_queries) for _ in range(num_concurrent)]
                all_latencies = []
                for future in concurrent.futures.as_completed(futures):
                    all_latencies.extend(future.result())
            
            if all_latencies:
                avg_latency = statistics.mean(all_latencies)
                # Under concurrent load, latency might be slightly higher
                assert avg_latency < 2.0, \
                    f"Average DNS latency under load should be < 2s, got {avg_latency:.3f}s"
        except FileNotFoundError:
            pytest.skip("dig command not available")


# Fixtures
@pytest.fixture
def internal_domain():
    """Get internal domain from environment or use default."""
    import os
    return os.getenv("INTERNAL_DNS_DOMAIN", "exnada.com")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-m", "performance"])
