#!/usr/bin/env bash
# Verify encrypted home directory setup implementation
# Checks that all required changes are in place

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_DIR="${REPO_ROOT}/ansible"

ERRORS=0
WARNINGS=0

echo "============================================================================"
echo "Verifying Encrypted Home Directory Setup"
echo "============================================================================"
echo ""

# Test 1: SSH hardening role has AuthorizedKeysFile directive
echo "[1/8] Checking SSH hardening role for AuthorizedKeysFile directive..."
if grep -q "AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u" "${ANSIBLE_DIR}/roles/ssh_hardening/tasks/main.yml"; then
    echo "  ✓ AuthorizedKeysFile directive found"
else
    echo "  ✗ ERROR: AuthorizedKeysFile directive not found in ssh_hardening role"
    ((ERRORS++))
fi

# Test 2: SSH hardening role creates system directory
echo "[2/8] Checking SSH hardening role creates system directory..."
if grep -q "/etc/ssh/authorized_keys.d" "${ANSIBLE_DIR}/roles/ssh_hardening/tasks/main.yml"; then
    echo "  ✓ System SSH keys directory creation found"
else
    echo "  ✗ ERROR: System SSH keys directory creation not found"
    ((ERRORS++))
fi

# Test 3: Bootstrap role writes keys to system location
echo "[3/8] Checking bootstrap role writes keys to system location..."
if grep -q '/etc/ssh/authorized_keys.d/{{ automation_user }}' "${ANSIBLE_DIR}/roles/common_bootstrap/tasks/main.yml"; then
    echo "  ✓ Bootstrap role writes automation keys to system location"
else
    echo "  ✗ ERROR: Bootstrap role does not write automation keys to system location"
    ((ERRORS++))
fi

# Test 4: Bootstrap role does NOT create home .ssh directory
echo "[4/8] Checking bootstrap role does not create home .ssh directory..."
if grep -q '/home/{{ automation_user }}/.ssh' "${ANSIBLE_DIR}/roles/common_bootstrap/tasks/main.yml"; then
    echo "  ⚠ WARNING: Bootstrap role still creates home .ssh directory (should be removed)"
    ((WARNINGS++))
else
    echo "  ✓ Bootstrap role does not create home .ssh directory"
fi

# Test 5: Common role writes keys to system location
echo "[5/8] Checking common role writes keys to system location..."
if grep -q "/etc/ssh/authorized_keys.d" "${ANSIBLE_DIR}/roles/common/tasks/main.yml"; then
    echo "  ✓ Common role writes keys to system location"
else
    echo "  ✗ ERROR: Common role does not write keys to system location"
    ((ERRORS++))
fi

# Test 6: LUKS role has encrypted home support
echo "[6/8] Checking LUKS role has encrypted home support..."
if grep -q "luks_encrypt_home" "${ANSIBLE_DIR}/roles/luks/tasks/main.yml"; then
    echo "  ✓ LUKS role has encrypted home support"
    
    # Check for key features
    if grep -q "luks_home_passphrase" "${ANSIBLE_DIR}/roles/luks/tasks/main.yml"; then
        echo "    ✓ Passphrase validation found"
    else
        echo "    ⚠ WARNING: Passphrase validation not found"
        ((WARNINGS++))
    fi
    
    if grep -q "/etc/crypttab" "${ANSIBLE_DIR}/roles/luks/tasks/main.yml"; then
        echo "    ✓ crypttab configuration found"
    else
        echo "    ⚠ WARNING: crypttab configuration not found"
        ((WARNINGS++))
    fi
    
    if grep -q "/etc/fstab" "${ANSIBLE_DIR}/roles/luks/tasks/main.yml"; then
        echo "    ✓ fstab configuration found"
    else
        echo "    ⚠ WARNING: fstab configuration not found"
        ((WARNINGS++))
    fi
else
    echo "  ✗ ERROR: LUKS role does not have encrypted home support"
    ((ERRORS++))
fi

# Test 7: Vega configuration has encrypted home settings
echo "[7/8] Checking vega host_vars configuration..."
if grep -q "luks_encrypt_home: true" "${ANSIBLE_DIR}/inventories/prod/host_vars/vega.yml"; then
    echo "  ✓ Vega has luks_encrypt_home enabled"
else
    echo "  ⚠ WARNING: Vega does not have luks_encrypt_home enabled"
    ((WARNINGS++))
fi

if grep -q "luks_home_device" "${ANSIBLE_DIR}/inventories/prod/host_vars/vega.yml"; then
    echo "  ✓ Vega has luks_home_device configured"
else
    echo "  ⚠ WARNING: Vega does not have luks_home_device configured"
    ((WARNINGS++))
fi

# Test 8: Secrets template has passphrase variable
echo "[8/8] Checking secrets template has passphrase variable..."
if grep -q "luks_home_passphrase" "${ANSIBLE_DIR}/inventories/prod/group_vars/all_secrets.yml.example"; then
    echo "  ✓ Secrets template has luks_home_passphrase variable"
else
    echo "  ✗ ERROR: Secrets template does not have luks_home_passphrase variable"
    ((ERRORS++))
fi

# Test 9: Helper script exists and is executable
echo "[9/9] Checking helper script..."
if [[ -f "${REPO_ROOT}/scripts/encrypt-home-partition.sh" ]]; then
    echo "  ✓ Helper script exists"
    if [[ -x "${REPO_ROOT}/scripts/encrypt-home-partition.sh" ]]; then
        echo "  ✓ Helper script is executable"
    else
        echo "  ✗ ERROR: Helper script is not executable"
        ((ERRORS++))
    fi
else
    echo "  ✗ ERROR: Helper script does not exist"
    ((ERRORS++))
fi

# Test 10: Documentation exists
echo "[10/10] Checking documentation..."
if grep -q "Encrypted Home Directories" "${REPO_ROOT}/README.md"; then
    echo "  ✓ README has encrypted home directories section"
    
    # Check for key documentation elements
    if grep -q "Partition Layout" "${REPO_ROOT}/README.md"; then
        echo "    ✓ Partition layout documented"
    else
        echo "    ⚠ WARNING: Partition layout not documented"
        ((WARNINGS++))
    fi
    
    if grep -q "luks_home_passphrase" "${REPO_ROOT}/README.md"; then
        echo "    ✓ Passphrase configuration documented"
    else
        echo "    ⚠ WARNING: Passphrase configuration not documented"
        ((WARNINGS++))
    fi
else
    echo "  ✗ ERROR: README does not have encrypted home directories section"
    ((ERRORS++))
fi

# Test 11: YAML syntax validation
echo "[11/11] Validating YAML syntax..."
YAML_FILES=(
    "${ANSIBLE_DIR}/roles/ssh_hardening/tasks/main.yml"
    "${ANSIBLE_DIR}/roles/common_bootstrap/tasks/main.yml"
    "${ANSIBLE_DIR}/roles/common/tasks/main.yml"
    "${ANSIBLE_DIR}/roles/luks/tasks/main.yml"
    "${ANSIBLE_DIR}/inventories/prod/host_vars/vega.yml"
    "${ANSIBLE_DIR}/inventories/prod/group_vars/all_secrets.yml.example"
)

YAML_ERRORS=0
for yaml_file in "${YAML_FILES[@]}"; do
    if command -v python3 &> /dev/null; then
        if ! python3 -c "import yaml; yaml.safe_load(open('${yaml_file}'))" 2>/dev/null; then
            echo "  ✗ ERROR: YAML syntax error in ${yaml_file}"
            ((YAML_ERRORS++))
        fi
    else
        echo "  ⚠ WARNING: python3 not available, skipping YAML validation"
        break
    fi
done

if [[ ${YAML_ERRORS} -eq 0 ]] && command -v python3 &> /dev/null; then
    echo "  ✓ All YAML files have valid syntax"
fi

# Summary
echo ""
echo "============================================================================"
echo "Verification Summary"
echo "============================================================================"
echo "Errors:   ${ERRORS}"
echo "Warnings: ${WARNINGS}"
echo ""

if [[ ${ERRORS} -gt 0 ]]; then
    echo "❌ VERIFICATION FAILED: ${ERRORS} error(s) found"
    echo "Please fix the errors above before proceeding."
    exit 1
elif [[ ${WARNINGS} -gt 0 ]]; then
    echo "⚠ VERIFICATION PASSED with ${WARNINGS} warning(s)"
    echo "Review warnings above - implementation may be incomplete."
    exit 0
else
    echo "✓ VERIFICATION PASSED: All checks passed"
    exit 0
fi
