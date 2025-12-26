# intergalactic

Manage a Raspberry Pi fleet (Gen1–Gen5) on **Debian Stable (Trixie)** using:
- **Bootstrap (headless SD provisioning)**: flash image + inject hostname + SSH keys + SSH hardening drop-in
- **Ansible**: full configuration once SSH is reachable

## Before use:
Prior to initial use, a ssh-key must be generated for ansible@control:
```
ssh-keygen -t ed25519 -f ~/.ssh/intergalactic_ansible -C "ansible@control"
```

## Best-practice identities
- **Automation account**: `ansible` (SSH key only, sudo via become, NOPASSWD)
- **Human account(s)**: e.g. `johndoe` (SSH key only), separate from automation for clear audit trails

## Non-negotiables
- No password-based login ever (SSH keys only)
- Tight SSH allowlist
- Default-deny firewall; only explicitly allowed ports
- Fail2ban: treat password attempts as hostile; long/“forever” bans + IP log
- Minimal packages; no X/desktop on headless nodes (desktop only on Gen5 workstation)

## Quick start

1) Edit keys + targets:
- `bootstrap/hosts.yaml` (image path, SD device, SSH keys)
- `ansible/inventories/prod/group_vars/all.yml` (keys)
- `ansible/inventories/prod/hosts.yml` (IPs)

2) Provision SD (headless):
```bash
sudo python3 scripts/provision_sd.py --host rigel
```

3) Apply Ansible:
```bash
./scripts/run-ansible.sh prod rigel-bootstrap
./scripts/run-ansible.sh prod rigel
```

Workstation:
```bash
sudo python3 scripts/provision_sd.py --host vega
./scripts/run-ansible.sh prod vega-bootstrap
./scripts/run-ansible.sh prod vega-desktop
```
