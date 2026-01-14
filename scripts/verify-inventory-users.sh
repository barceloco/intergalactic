#!/usr/bin/env bash
# Verification script to ensure all hosts use correct users in inventory files
# Bootstrap inventory: ALL must use 'armand'
# Production inventory: ALL must use 'ansible'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_INV="${SCRIPT_DIR}/ansible/inventories/prod/hosts-bootstrap.yml"
PRODUCTION_INV="${SCRIPT_DIR}/ansible/inventories/prod/hosts-production.yml"

if [[ ! -f "${BOOTSTRAP_INV}" ]] || [[ ! -f "${PRODUCTION_INV}" ]]; then
  echo "ERROR: Inventory files not found!"
  exit 1
fi

# Check if Python 3 and PyYAML are available
if ! command -v python3 &> /dev/null; then
  echo "ERROR: python3 not found"
  exit 1
fi

python3 << 'PYTHON_SCRIPT'
import sys
import yaml

def get_hosts(inv):
    """Extract all hosts from inventory structure"""
    hosts = {}
    for location in inv['all']['children'].values():
        for rpi_group in location.get('children', {}).values():
            for hostname, config in rpi_group.get('hosts', {}).items():
                hosts[hostname] = config
    return hosts

# Load bootstrap inventory
try:
    with open('ansible/inventories/prod/hosts-bootstrap.yml', 'r') as f:
        bootstrap = yaml.safe_load(f)
except Exception as e:
    print(f"ERROR: Failed to load bootstrap inventory: {e}")
    sys.exit(1)

# Load production inventory
try:
    with open('ansible/inventories/prod/hosts-production.yml', 'r') as f:
        production = yaml.safe_load(f)
except Exception as e:
    print(f"ERROR: Failed to load production inventory: {e}")
    sys.exit(1)

bootstrap_hosts = get_hosts(bootstrap)
production_hosts = get_hosts(production)

# Verify bootstrap inventory
print("=" * 70)
print("VERIFYING BOOTSTRAP INVENTORY (must all use 'armand'):")
print("=" * 70)
bootstrap_errors = []
for host, config in sorted(bootstrap_hosts.items()):
    user = config.get('ansible_user', 'NOT SET')
    if user != "armand":
        bootstrap_errors.append(f"  ✗ {host:15} uses '{user}' (should be 'armand')")
    else:
        print(f"  ✓ {host:15} -> {user}")

# Verify production inventory
print("\n" + "=" * 70)
print("VERIFYING PRODUCTION INVENTORY (must all use 'ansible'):")
print("=" * 70)
production_errors = []
for host, config in sorted(production_hosts.items()):
    user = config.get('ansible_user', 'NOT SET')
    if user != "ansible":
        production_errors.append(f"  ✗ {host:15} uses '{user}' (should be 'ansible')")
    else:
        print(f"  ✓ {host:15} -> {user}")

# Check for missing hosts
bootstrap_hostnames = set(bootstrap_hosts.keys())
production_hostnames = set(production_hosts.keys())
missing_in_bootstrap = production_hostnames - bootstrap_hostnames
missing_in_production = bootstrap_hostnames - production_hostnames

# Report results
print("\n" + "=" * 70)
if bootstrap_errors or production_errors or missing_in_bootstrap or missing_in_production:
    print("✗ VERIFICATION FAILED!")
    print("=" * 70)
    if bootstrap_errors:
        print("\nBootstrap inventory errors:")
        for error in bootstrap_errors:
            print(error)
    if production_errors:
        print("\nProduction inventory errors:")
        for error in production_errors:
            print(error)
    if missing_in_bootstrap:
        print(f"\nHosts in production but missing in bootstrap: {', '.join(missing_in_bootstrap)}")
    if missing_in_production:
        print(f"\nHosts in bootstrap but missing in production: {', '.join(missing_in_production)}")
    sys.exit(1)
else:
    print("✓ VERIFICATION PASSED!")
    print("=" * 70)
    print(f"  ✓ All {len(bootstrap_hosts)} hosts in bootstrap use 'armand'")
    print(f"  ✓ All {len(production_hosts)} hosts in production use 'ansible'")
    print(f"  ✓ All hosts are present in both inventories")
    print("=" * 70)
    sys.exit(0)
PYTHON_SCRIPT

EXIT_CODE=$?
if [[ ${EXIT_CODE} -eq 0 ]]; then
  echo ""
  echo "✓ All inventory files are correctly configured!"
else
  echo ""
  echo "✗ Inventory verification failed. Please fix the errors above."
fi

exit ${EXIT_CODE}
