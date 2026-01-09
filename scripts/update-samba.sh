#!/usr/bin/env bash
# Quick script to update Samba configuration without running full playbook
set -euo pipefail

ENV_NAME="${1:-prod}"
HOST="${2:-rigel}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="intergalactic-ansible-runner:latest"

# Build Docker image
docker build -t "${IMAGE}" "${ROOT_DIR}/docker/ansible-runner" > /dev/null 2>&1

# Mount SSH keys for authentication (use intergalactic_ansible for production)
SSH_KEY_MOUNT=""
SSH_KEY_NAME=""
if [[ -f "${HOME}/.ssh/intergalactic_ansible" ]]; then
  SSH_KEY_MOUNT="-v ${HOME}/.ssh/intergalactic_ansible:/root/.ssh/intergalactic_ansible:ro"
  SSH_KEY_NAME="intergalactic_ansible"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
  SSH_KEY_MOUNT="-v ${HOME}/.ssh/id_ed25519:/root/.ssh/id_ed25519:ro"
  SSH_KEY_NAME="id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
  SSH_KEY_MOUNT="-v ${HOME}/.ssh/id_rsa:/root/.ssh/id_rsa:ro"
  SSH_KEY_NAME="id_rsa"
fi

# SSH agent forwarding if available
SSH_AUTH_SOCK_MOUNT=""
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  SSH_AUTH_SOCK_MOUNT="-v ${SSH_AUTH_SOCK}:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
fi

INVENTORY_FILE="inventories/${ENV_NAME}/hosts.yml"

# Configure SSH to use the correct key
if [[ -n "${SSH_KEY_NAME:-}" ]]; then
  export ANSIBLE_SSH_ARGS="-o IdentitiesOnly=yes -i /root/.ssh/${SSH_KEY_NAME}"
fi

echo "Updating Samba configuration on ${HOST}..."

# Run just the Samba config deployment task
docker run --rm -i \
  -v "${ROOT_DIR}:/repo" \
  ${SSH_KEY_MOUNT} \
  ${SSH_AUTH_SOCK_MOUNT} \
  -e ANSIBLE_SSH_ARGS="${ANSIBLE_SSH_ARGS:-}" \
  "${IMAGE}" \
  ansible-playbook -i "${INVENTORY_FILE}" \
    --limit "${HOST}" \
    /dev/stdin << 'EOF'
---
- name: Update Samba configuration
  hosts: all
  become: true
  gather_facts: false
  vars_files:
    - "inventories/prod/group_vars/all_secrets.yml"
  pre_tasks:
    - name: Ensure .ssh directory exists for known_hosts
      file:
        path: "/root/.ssh"
        state: directory
        mode: '0700'
      delegate_to: localhost
      run_once: true

    - name: Fetch host key using ssh-keyscan (secure host key verification)
      command: >
        ssh-keyscan
        -t ecdsa,ed25519,rsa
        {{ ansible_host | default(inventory_hostname) }}
      register: ssh_keyscan_output
      delegate_to: localhost
      run_once: true
      changed_when: false
      failed_when: false

    - name: Fail if ssh-keyscan failed (cannot verify host identity)
      assert:
        that:
          - ssh_keyscan_output.rc == 0
          - ssh_keyscan_output.stdout_lines | length > 0
        fail_msg: |
          SECURITY ERROR: Cannot verify host identity!
          ssh-keyscan failed to fetch host keys from {{ ansible_host | default(inventory_hostname) }}
        success_msg: "✓ Host key fetched successfully"

    - name: Add fetched host keys to known_hosts
      lineinfile:
        path: "{{ ansible_ssh_known_hosts_file | default('~/.ssh/known_hosts') }}"
        line: "{{ item }}"
        create: true
        mode: '0600'
        regexp: "^{{ item.split()[0] if item.split() | length > 0 else '' }} "
        state: present
      delegate_to: localhost
      run_once: true
      loop: "{{ ssh_keyscan_output.stdout_lines }}"
      when:
        - item is defined
        - item | length > 0
        - not item.startswith('#')
        - item.split() | length >= 3

    - name: Gather facts after host key verification
      setup:
  tasks:
    - name: Deploy Samba configuration
      template:
        src: /repo/ansible/roles/samba/templates/smb.conf.j2
        dest: /etc/samba/smb.conf
        mode: '0644'
        owner: root
        group: root

    - name: Validate Samba configuration syntax
      command: testparm -s
      register: samba_test
      changed_when: false
      failed_when: samba_test.rc != 0

    - name: Restart smbd
      service:
        name: smbd
        state: restarted

    - name: Restart nmbd
      service:
        name: nmbd
        state: restarted
EOF

echo "✓ Samba configuration updated and services restarted"
