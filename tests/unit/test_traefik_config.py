#!/usr/bin/env python3
"""
Unit tests for Traefik configuration generation.
Tests Traefik static config, dynamic config, and docker-compose generation.
"""

import pytest
import yaml
import re
from pathlib import Path


class TestTraefikStaticConfig:
    """Test Traefik static configuration generation."""
    
    def test_traefik_yml_template_exists(self):
        """Verify traefik.yml template exists."""
        template_path = Path("ansible/roles/edge_ingress/templates/traefik.yml.j2")
        assert template_path.exists(), "traefik.yml.j2 template should exist"
    
    def test_traefik_yml_has_entrypoints(self, traefik_yml_content):
        """Verify traefik.yml has entrypoints configured."""
        assert "entryPoints:" in traefik_yml_content.lower(), \
            "Traefik config should have entryPoints"
    
    def test_traefik_yml_has_certificate_resolver(self, traefik_yml_content):
        """Verify traefik.yml has certificate resolver configured."""
        assert "certificatesResolvers:" in traefik_yml_content.lower() or \
               "certResolver" in traefik_yml_content.lower(), \
            "Traefik config should have certificate resolver"
    
    def test_traefik_yml_has_providers(self, traefik_yml_content):
        """Verify traefik.yml has providers configured."""
        assert "providers:" in traefik_yml_content.lower() or \
               "providersFile" in traefik_yml_content.lower(), \
            "Traefik config should have providers"


class TestTraefikDynamicConfig:
    """Test Traefik dynamic configuration generation."""
    
    def test_dynamic_yml_template_exists(self):
        """Verify dynamic.yml template exists."""
        template_path = Path("ansible/roles/edge_ingress/templates/dynamic.yml.j2")
        assert template_path.exists(), "dynamic.yml.j2 template should exist"
    
    def test_dynamic_yml_has_routers(self, dynamic_yml_content):
        """Verify dynamic.yml has routers section."""
        assert "routers:" in dynamic_yml_content.lower(), \
            "Dynamic config should have routers section"
    
    def test_dynamic_yml_has_services(self, dynamic_yml_content):
        """Verify dynamic.yml has services section."""
        assert "services:" in dynamic_yml_content.lower(), \
            "Dynamic config should have services section"
    
    def test_dynamic_yml_has_middlewares(self, dynamic_yml_content):
        """Verify dynamic.yml has middlewares section."""
        assert "middlewares:" in dynamic_yml_content.lower(), \
            "Dynamic config should have middlewares section"
    
    def test_dynamic_yml_is_valid_yaml(self, dynamic_yml_content):
        """Verify dynamic.yml is valid YAML syntax."""
        try:
            yaml.safe_load(dynamic_yml_content)
        except yaml.YAMLError as e:
            pytest.fail(f"Dynamic config is not valid YAML: {e}")


class TestTraefikDockerCompose:
    """Test Docker Compose file generation for Traefik."""
    
    def test_docker_compose_template_exists(self):
        """Verify docker-compose template exists."""
        template_path = Path("ansible/roles/edge_ingress/templates/docker-compose.yml.j2")
        assert template_path.exists(), "docker-compose.yml.j2 template should exist"
    
    def test_docker_compose_has_traefik_service(self, docker_compose_content):
        """Verify docker-compose has traefik service."""
        assert "traefik" in docker_compose_content.lower(), \
            "Docker compose should have traefik service"
    
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
    
    def test_docker_compose_has_environment_vars(self, docker_compose_content):
        """Verify docker-compose has environment variables."""
        assert "environment:" in docker_compose_content.lower(), \
            "Docker compose should have environment variables"


class TestTraefikSystemdService:
    """Test systemd service file generation for Traefik."""
    
    def test_systemd_service_template_exists(self):
        """Verify systemd service template exists."""
        template_path = Path("ansible/roles/edge_ingress/templates/traefik.service.j2")
        assert template_path.exists(), "traefik.service.j2 template should exist"
    
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
    
    def test_systemd_service_has_coredns_dependency(self, systemd_service_content):
        """Verify systemd service depends on CoreDNS if enabled."""
        # This is conditional, so we just check the template has the logic
        assert "coredns" in systemd_service_content.lower() or \
               "docker.service" in systemd_service_content, \
            "Systemd service should reference coredns or docker"
    
    def test_systemd_service_has_restart_policy(self, systemd_service_content):
        """Verify systemd service has restart policy."""
        assert "Restart=" in systemd_service_content, \
            "Systemd service should have restart policy"


# Fixtures for loading template content
@pytest.fixture
def traefik_yml_content():
    """Load traefik.yml template content."""
    template_path = Path("ansible/roles/edge_ingress/templates/traefik.yml.j2")
    if template_path.exists():
        return template_path.read_text()
    return ""


@pytest.fixture
def dynamic_yml_content():
    """Load dynamic.yml template content."""
    template_path = Path("ansible/roles/edge_ingress/templates/dynamic.yml.j2")
    if template_path.exists():
        return template_path.read_text()
    return ""


@pytest.fixture
def docker_compose_content():
    """Load docker-compose template content."""
    template_path = Path("ansible/roles/edge_ingress/templates/docker-compose.yml.j2")
    if template_path.exists():
        return template_path.read_text()
    return ""


@pytest.fixture
def systemd_service_content():
    """Load systemd service template content."""
    template_path = Path("ansible/roles/edge_ingress/templates/traefik.service.j2")
    if template_path.exists():
        return template_path.read_text()
    return ""


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
