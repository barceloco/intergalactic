#!/usr/bin/env python3
"""
Unit tests for Ansible variable validation.
Tests that required variables are defined and have correct types.
"""

import pytest
import yaml
from pathlib import Path


class TestInternalDNSVariables:
    """Test internal_dns role variables."""
    
    def test_internal_dns_defaults_exist(self):
        """Verify internal_dns defaults file exists."""
        defaults_path = Path("ansible/roles/internal_dns/defaults/main.yml")
        assert defaults_path.exists(), "internal_dns defaults should exist"
    
    def test_internal_dns_domain_defined(self, internal_dns_defaults):
        """Verify internal_dns_domain is defined."""
        assert "internal_dns_domain" in internal_dns_defaults, \
            "internal_dns_domain should be defined in defaults"
    
    def test_internal_dns_private_hosts_defined(self, internal_dns_defaults):
        """Verify internal_dns_private_hosts is defined."""
        assert "internal_dns_private_hosts" in internal_dns_defaults, \
            "internal_dns_private_hosts should be defined in defaults"
    
    def test_internal_dns_container_name_defined(self, internal_dns_defaults):
        """Verify internal_dns_container_name is defined."""
        assert "internal_dns_container_name" in internal_dns_defaults, \
            "internal_dns_container_name should be defined in defaults"
    
    def test_internal_dns_data_dir_defined(self, internal_dns_defaults):
        """Verify internal_dns_data_dir is defined."""
        assert "internal_dns_data_dir" in internal_dns_defaults, \
            "internal_dns_data_dir should be defined in defaults"


class TestEdgeIngressVariables:
    """Test edge_ingress role variables."""
    
    def test_edge_ingress_defaults_exist(self):
        """Verify edge_ingress defaults file exists."""
        defaults_path = Path("ansible/roles/edge_ingress/defaults/main.yml")
        assert defaults_path.exists(), "edge_ingress defaults should exist"
    
    def test_edge_ingress_domain_defined(self, edge_ingress_defaults):
        """Verify edge_ingress_domain is defined."""
        assert "edge_ingress_domain" in edge_ingress_defaults, \
            "edge_ingress_domain should be defined in defaults"
    
    def test_edge_ingress_acme_email_defined(self, edge_ingress_defaults):
        """Verify edge_ingress_acme_email is defined."""
        assert "edge_ingress_acme_email" in edge_ingress_defaults, \
            "edge_ingress_acme_email should be defined in defaults"
    
    def test_edge_ingress_container_name_defined(self, edge_ingress_defaults):
        """Verify edge_ingress_container_name is defined."""
        assert "edge_ingress_container_name" in edge_ingress_defaults, \
            "edge_ingress_container_name should be defined in defaults"
    
    def test_edge_ingress_data_dir_defined(self, edge_ingress_defaults):
        """Verify edge_ingress_data_dir is defined."""
        assert "edge_ingress_data_dir" in edge_ingress_defaults, \
            "edge_ingress_data_dir should be defined in defaults"
    
    def test_edge_ingress_routes_defined(self, edge_ingress_defaults):
        """Verify edge_ingress_routes is defined."""
        assert "edge_ingress_routes" in edge_ingress_defaults, \
            "edge_ingress_routes should be defined in defaults"


class TestVariableTypes:
    """Test that variables have correct types."""
    
    def test_internal_dns_private_hosts_is_list(self, internal_dns_defaults):
        """Verify internal_dns_private_hosts is a list."""
        hosts = internal_dns_defaults.get("internal_dns_private_hosts", [])
        assert isinstance(hosts, list), \
            "internal_dns_private_hosts should be a list"
    
    def test_edge_ingress_routes_is_list(self, edge_ingress_defaults):
        """Verify edge_ingress_routes is a list."""
        routes = edge_ingress_defaults.get("edge_ingress_routes", [])
        assert isinstance(routes, list), \
            "edge_ingress_routes should be a list"
    
    def test_internal_dns_domain_is_string(self, internal_dns_defaults):
        """Verify internal_dns_domain is a string."""
        domain = internal_dns_defaults.get("internal_dns_domain", "")
        assert isinstance(domain, str), \
            "internal_dns_domain should be a string"
    
    def test_edge_ingress_domain_is_string(self, edge_ingress_defaults):
        """Verify edge_ingress_domain is a string."""
        domain = edge_ingress_defaults.get("edge_ingress_domain", "")
        assert isinstance(domain, str), \
            "edge_ingress_domain should be a string"


# Fixtures for loading defaults
@pytest.fixture
def internal_dns_defaults():
    """Load internal_dns defaults."""
    defaults_path = Path("ansible/roles/internal_dns/defaults/main.yml")
    if defaults_path.exists():
        with open(defaults_path) as f:
            return yaml.safe_load(f) or {}
    return {}


@pytest.fixture
def edge_ingress_defaults():
    """Load edge_ingress defaults."""
    defaults_path = Path("ansible/roles/edge_ingress/defaults/main.yml")
    if defaults_path.exists():
        with open(defaults_path) as f:
            return yaml.safe_load(f) or {}
    return {}


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
