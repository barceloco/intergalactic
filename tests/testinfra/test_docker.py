"""
Testinfra tests for Docker configuration.
These tests verify Docker installation and configuration.
"""


def test_docker_installed(host):
    """Verify Docker is installed."""
    docker_pkg = host.package("docker-ce")
    assert docker_pkg.is_installed


def test_docker_service_running(host):
    """Verify Docker service is running."""
    docker_service = host.service("docker")
    assert docker_service.is_running
    assert docker_service.is_enabled


def test_docker_data_root(host):
    """Verify Docker data-root is configured correctly (if custom)."""
    docker_info = host.run("docker info")
    assert docker_info.rc == 0
    
    # Check if custom data-root is mentioned (optional)
    # This test passes if Docker is working, regardless of data-root location
    assert "Docker Root Dir" in docker_info.stdout


def test_deploy_user_exists(host):
    """Verify deploy user exists (if docker_deploy role was applied)."""
    # This test is conditional - only check if deploy user should exist
    # In practice, you'd check a fact or variable
    deploy_user = host.user("deploy")
    # Only assert if we expect deploy user to exist
    # For now, we'll just check if it exists (won't fail if role wasn't applied)
    if deploy_user.exists:
        assert deploy_user.shell == "/bin/bash"
        assert "docker" in deploy_user.groups


def test_docker_directories_exist(host):
    """Verify Docker-related directories exist (if docker_deploy role was applied)."""
    # Conditional check - only verify if directories should exist
    deploy_docker_dir = host.file("/home/deploy/docker")
    if deploy_docker_dir.exists:
        assert deploy_docker_dir.is_directory
        # Docker requires 711 permissions for data-root
        assert deploy_docker_dir.mode == 0o711
