"""
Testinfra tests for common system configuration.
These tests verify that basic system setup is correct.
"""


def test_ansible_user_exists(host):
    """Verify ansible user exists and has correct shell."""
    ansible_user = host.user("ansible")
    assert ansible_user.exists
    assert ansible_user.shell == "/bin/bash"


def test_ansible_user_sudo(host):
    """Verify ansible user has passwordless sudo."""
    result = host.run("sudo -n -u ansible whoami")
    assert result.rc == 0
    assert result.stdout.strip() == "ansible"


def test_ssh_keys_directory(host):
    """Verify SSH keys directory exists."""
    keys_dir = host.file("/etc/ssh/authorized_keys.d")
    assert keys_dir.exists
    assert keys_dir.is_directory
    assert keys_dir.mode == 0o755


def test_ssh_password_auth_disabled(host):
    """Verify password authentication is disabled."""
    sshd_config = host.file("/etc/ssh/sshd_config.d/10-intergalactic-bootstrap.conf")
    if sshd_config.exists:
        content = sshd_config.content_string
        assert "PasswordAuthentication no" in content or "PasswordAuthentication No" in content


def test_hostname_set(host):
    """Verify hostname is set (if configured)."""
    # This is a basic check - hostname should exist
    hostname = host.run("hostname")
    assert hostname.rc == 0
    assert len(hostname.stdout.strip()) > 0
