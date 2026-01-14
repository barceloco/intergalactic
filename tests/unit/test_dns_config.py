#!/usr/bin/env python3
"""
Unit tests for DNS configuration generation.
Tests CoreDNS Corefile and zone file generation.
"""

import pytest
import yaml
import re
from pathlib import Path


class TestCorefileGeneration:
    """Test CoreDNS Corefile generation."""
    
    def test_corefile_template_exists(self):
        """Verify Corefile template exists."""
        template_path = Path("ansible/roles/internal_dns/templates/Corefile.j2")
        assert template_path.exists(), "Corefile.j2 template should exist"
    
    def test_corefile_has_required_sections(self, corefile_content):
        """Verify Corefile has required sections."""
        required_sections = [
            ".:53",
            "forward",
            "file",
        ]
        for section in required_sections:
            assert section in corefile_content, f"Corefile should contain '{section}'"
    
    def test_corefile_has_upstream_servers(self, corefile_content):
        """Verify Corefile has upstream DNS servers configured."""
        # Should have forward directive with upstream servers
        assert "forward" in corefile_content.lower(), "Corefile should have forward directive"
    
    def test_corefile_has_zone_file_reference(self, corefile_content):
        """Verify Corefile references zone file."""
        # Should reference the zone file
        assert "db." in corefile_content or "file" in corefile_content.lower(), \
            "Corefile should reference zone file"


class TestZoneFileGeneration:
    """Test DNS zone file generation."""
    
    def test_zone_file_template_exists(self):
        """Verify zone file template exists."""
        template_path = Path("ansible/roles/internal_dns/templates/db.company.com.j2")
        assert template_path.exists(), "db.company.com.j2 template should exist"
    
    def test_zone_file_has_soa_record(self, zone_file_content):
        """Verify zone file has SOA record."""
        assert "SOA" in zone_file_content, "Zone file should have SOA record"
    
    def test_zone_file_has_ns_record(self, zone_file_content):
        """Verify zone file has NS record."""
        assert "NS" in zone_file_content, "Zone file should have NS record"
    
    def test_zone_file_has_a_records(self, zone_file_content):
        """Verify zone file has A records for hosts."""
        # Should have at least one A record
        a_record_pattern = r'\s+A\s+'
        assert re.search(a_record_pattern, zone_file_content), \
            "Zone file should have A records"


class TestDockerComposeGeneration:
    """Test Docker Compose file generation for CoreDNS."""
    
    def test_docker_compose_template_exists(self):
        """Verify docker-compose template exists."""
        template_path = Path("ansible/roles/internal_dns/templates/docker-compose.yml.j2")
        assert template_path.exists(), "docker-compose.yml.j2 template should exist"
    
    def test_docker_compose_has_coredns_service(self, docker_compose_content):
        """Verify docker-compose has coredns service."""
        assert "coredns" in docker_compose_content.lower(), \
            "Docker compose should have coredns service"
    
    def test_docker_compose_has_restart_policy(self, docker_compose_content):
        """Verify docker-compose has restart policy."""
        assert "restart:" in docker_compose_content.lower(), \
            "Docker compose should have restart policy"
    
    def test_docker_compose_has_network_mode_host(self, docker_compose_content):
        """Verify docker-compose uses host network mode."""
        assert "network_mode: host" in docker_compose_content.lower(), \
            "Docker compose should use host network mode"
    
    def test_docker_compose_has_volume_mounts(self, docker_compose_content):
        """Verify docker-compose has volume mounts."""
        assert "volumes:" in docker_compose_content.lower(), \
            "Docker compose should have volume mounts"


class TestSystemdServiceGeneration:
    """Test systemd service file generation for CoreDNS."""
    
    def test_systemd_service_template_exists(self):
        """Verify systemd service template exists."""
        template_path = Path("ansible/roles/internal_dns/templates/coredns.service.j2")
        assert template_path.exists(), "coredns.service.j2 template should exist"
    
    def test_systemd_service_has_unit_section(self, systemd_service_content):
        """Verify systemd service has [Unit] section."""
        assert "[Unit]" in systemd_service_content, \
            "Systemd service should have [Unit] section"
    
    def test_systemd_service_has_service_section(self, systemd_service_content):
        """Verify systemd service has [Service] section."""
        assert "[Service]" in systemd_service_content, \
            "Systemd service should have [Service] section"
    
    def test_systemd_service_has_install_section(self, systemd_service_content):
        """Verify systemd service has [Install] section."""
        assert "[Install]" in systemd_service_content, \
            "Systemd service should have [Install] section"
    
    def test_systemd_service_has_docker_dependency(self, systemd_service_content):
        """Verify systemd service depends on Docker."""
        assert "docker.service" in systemd_service_content, \
            "Systemd service should depend on docker.service"
    
    def test_systemd_service_has_restart_policy(self, systemd_service_content):
        """Verify systemd service has restart policy."""
        assert "Restart=" in systemd_service_content, \
            "Systemd service should have restart policy"


# Fixtures for loading template content
@pytest.fixture
def corefile_content():
    """Load Corefile template content."""
    template_path = Path("ansible/roles/internal_dns/templates/Corefile.j2")
    if template_path.exists():
        return template_path.read_text()
    return ""


@pytest.fixture
def zone_file_content():
    """Load zone file template content."""
    template_path = Path("ansible/roles/internal_dns/templates/db.company.com.j2")
    if template_path.exists():
        return template_path.read_text()
    return ""


@pytest.fixture
def docker_compose_content():
    """Load docker-compose template content."""
    template_path = Path("ansible/roles/internal_dns/templates/docker-compose.yml.j2")
    if template_path.exists():
        return template_path.read_text()
    return ""


@pytest.fixture
def systemd_service_content():
    """Load systemd service template content."""
    template_path = Path("ansible/roles/internal_dns/templates/coredns.service.j2")
    if template_path.exists():
        return template_path.read_text()
    return ""


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
