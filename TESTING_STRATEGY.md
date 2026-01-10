# Ansible Testing Strategy

## Overview

This document outlines a testing strategy for the intergalactic Ansible project. Testing ensures playbooks and roles work correctly, remain idempotent, and don't break existing functionality.

## Current State

**Testing Status**: ❌ **NO FORMAL TESTING**

- No automated tests
- No linting in CI/CD
- Manual testing only
- No test infrastructure

## Testing Tools for Ansible

### 1. ansible-lint (Code Quality)

**Purpose**: Lint Ansible playbooks and roles for best practices and common errors

**Installation**:
```bash
pip install ansible-lint
```

**Usage**:
```bash
# Lint all playbooks and roles
ansible-lint ansible/

# Lint specific file
ansible-lint ansible/playbooks/rigel-production.yml

# Auto-fix some issues
ansible-lint --fix ansible/
```

**Benefits**:
- Catches YAML syntax errors
- Enforces Ansible best practices
- Identifies deprecated modules
- Checks for security issues

**Recommendation**: ✅ **IMPLEMENT IMMEDIATELY** - Low effort, high value

### 2. yamllint (YAML Syntax)

**Purpose**: Lint YAML files for syntax and style

**Installation**:
```bash
pip install yamllint
```

**Usage**:
```bash
# Lint all YAML files
yamllint ansible/

# With custom config
yamllint -c .yamllint ansible/
```

**Benefits**:
- Catches YAML syntax errors early
- Enforces consistent formatting
- Prevents common YAML pitfalls

**Recommendation**: ✅ **IMPLEMENT IMMEDIATELY** - Low effort, high value

### 3. Molecule (Role Testing)

**Purpose**: Test Ansible roles in isolated environments

**Installation**:
```bash
pip install molecule molecule-plugins[docker]
```

**What it does**:
- Creates test instances (Docker, Vagrant, etc.)
- Runs playbooks against test instances
- Verifies idempotency
- Runs tests (Testinfra, Goss, etc.)

**Example Structure**:
```
ansible/roles/docker_deploy/
  molecule/
    default/
      molecule.yml      # Test configuration
      converge.yml      # Test playbook
      verify.yml        # Verification tests
```

**Benefits**:
- Tests roles in isolation
- Verifies idempotency
- Tests across multiple OS versions
- Catches regressions

**Recommendation**: ⚠️ **CONSIDER FOR KEY ROLES** - Medium effort, high value for complex roles

**Best Candidates**:
- `docker_deploy` - Complex role with many features
- `internal_dns` - New role, should be tested
- `edge_ingress` - New role, should be tested
- `firewall_nftables` - Security-critical

### 4. Testinfra (Infrastructure Testing)

**Purpose**: Write unit tests for server state

**Installation**:
```bash
pip install testinfra
```

**Usage**:
```bash
# Test against Ansible inventory
pytest --hosts=ansible://rigel --ansible-inventory=ansible/inventories/prod/hosts.yml

# Test specific host
pytest --hosts=ansible://rigel test_rigel.py
```

**Example Test**:
```python
def test_docker_is_installed(host):
    assert host.package("docker-ce").is_installed

def test_firewall_is_running(host):
    assert host.service("nftables").is_running
    assert host.service("nftables").is_enabled
```

**Benefits**:
- Tests actual server state
- Can use Ansible inventory
- Integrates with pytest
- Catches configuration drift

**Recommendation**: ⚠️ **CONSIDER FOR PRODUCTION** - Medium effort, high value for production verification

### 5. ansible-playbook --check (Dry Run)

**Purpose**: Test playbooks without making changes

**Usage**:
```bash
ansible-playbook --check --diff ansible/playbooks/rigel-production.yml
```

**Benefits**:
- Quick validation
- No changes to systems
- Shows what would change
- Catches syntax errors

**Recommendation**: ✅ **USE REGULARLY** - Already available, should be used more

### 6. ansible-playbook --syntax-check

**Purpose**: Check playbook syntax without running

**Usage**:
```bash
ansible-playbook --syntax-check ansible/playbooks/rigel-production.yml
```

**Benefits**:
- Very fast
- Catches syntax errors
- No system access needed

**Recommendation**: ✅ **USE IN CI/CD** - Should be in every commit hook

## Recommended Testing Strategy

### Phase 1: Immediate (Low Effort, High Value)

**Goal**: Catch errors before they reach production

1. **ansible-lint** - Add to pre-commit hook
   ```bash
   # .pre-commit-config.yaml
   repos:
     - repo: https://github.com/ansible/ansible-lint
       rev: v6.x
       hooks:
         - id: ansible-lint
   ```

2. **yamllint** - Add to pre-commit hook
   ```bash
   repos:
     - repo: https://github.com/adrienverge/yamllint
       rev: v1.x
       hooks:
         - id: yamllint
   ```

3. **Syntax check in CI/CD** - Add to GitHub Actions / GitLab CI
   ```yaml
   - name: Check Ansible syntax
     run: |
       ansible-playbook --syntax-check ansible/playbooks/*.yml
   ```

**Effort**: 2-4 hours
**Value**: High - Catches most errors early

### Phase 2: Short-term (Medium Effort, High Value)

**Goal**: Test roles in isolation

1. **Molecule for key roles**:
   - `docker_deploy`
   - `internal_dns`
   - `edge_ingress`
   - `firewall_nftables`

2. **Test idempotency**:
   ```bash
   molecule test
   ```

**Effort**: 1-2 days per role
**Value**: High - Prevents role regressions

### Phase 3: Long-term (High Effort, High Value)

**Goal**: Comprehensive testing

1. **Testinfra for production verification**:
   - Test actual server state
   - Verify configuration compliance
   - Catch configuration drift

2. **Integration tests**:
   - Test full three-phase deployment
   - Test role interactions
   - Test network transitions

**Effort**: 1-2 weeks
**Value**: Very High - Production confidence

## Implementation Plan

### Step 1: Add Linting (Week 1)

1. Install ansible-lint and yamllint
2. Create `.ansible-lint` config
3. Create `.yamllint` config
4. Add to pre-commit hook
5. Fix existing linting issues

### Step 2: Add Syntax Checks (Week 1)

1. Add syntax check to CI/CD
2. Add to pre-commit hook
3. Document in README

### Step 3: Add Molecule for Key Roles (Week 2-3)

1. Install Molecule
2. Create molecule config for `docker_deploy`
3. Create molecule config for `internal_dns`
4. Create molecule config for `edge_ingress`
5. Create molecule config for `firewall_nftables`
6. Add to CI/CD

### Step 4: Add Testinfra (Week 4+)

1. Install Testinfra
2. Create test suite for production hosts
3. Add to CI/CD
4. Schedule regular runs

## Example Configuration Files

### .ansible-lint

```yaml
---
# Ansible Lint configuration
skip_list:
  - yaml[line-length]  # Allow longer lines if needed
  - name[casing]        # Allow lowercase names if preferred
  - name[template]      # Allow template names

exclude_paths:
  - .cache/
  - .git/
  - molecule/

verbosity: 1
```

### .yamllint

```yaml
---
extends: default

rules:
  line-length:
    max: 120
    level: warning
  indentation:
    spaces: 2
    indent-sequences: true
  comments:
    min-spaces-from-content: 1
```

### .pre-commit-config.yaml

```yaml
---
repos:
  - repo: https://github.com/ansible/ansible-lint
    rev: v6.x
    hooks:
      - id: ansible-lint
        files: ansible/.*\.(yml|yaml)$
  
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.x
    hooks:
      - id: yamllint
        files: ansible/.*\.(yml|yaml)$
```

## Testing Workflow

### Before Committing

1. Run `ansible-lint` on changed files
2. Run `yamllint` on changed files
3. Run `ansible-playbook --syntax-check` on changed playbooks
4. Run `ansible-playbook --check` on changed playbooks (if possible)

### Before Merging

1. All linting passes
2. All syntax checks pass
3. Molecule tests pass (for changed roles)
4. Manual testing on staging (if available)

### In Production

1. Run Testinfra tests regularly
2. Monitor for configuration drift
3. Verify idempotency periodically

## Benefits of Testing

1. **Catch errors early** - Before they reach production
2. **Prevent regressions** - Ensure changes don't break existing functionality
3. **Documentation** - Tests serve as executable documentation
4. **Confidence** - Deploy with confidence
5. **Speed** - Automated tests are faster than manual testing

## Cost-Benefit Analysis

### Low Effort, High Value ✅

- **ansible-lint**: 2 hours setup, catches 80% of errors
- **yamllint**: 1 hour setup, catches syntax errors
- **Syntax checks**: 1 hour setup, catches playbook errors

**Total**: 4 hours, prevents most errors

### Medium Effort, High Value ⚠️

- **Molecule for 4 roles**: 2-3 days, tests role isolation
- **Testinfra**: 1 week, tests production state

**Total**: 1-2 weeks, comprehensive testing

## Recommendation

**Start with Phase 1** (linting and syntax checks):
- Low effort (4 hours)
- High value (catches most errors)
- Immediate benefits
- No infrastructure needed

**Then consider Phase 2** (Molecule for key roles):
- Medium effort (1-2 weeks)
- High value (prevents role regressions)
- Requires Docker/Vagrant
- Best for complex roles

**Finally Phase 3** (Testinfra and integration tests):
- High effort (2-4 weeks)
- Very high value (production confidence)
- Requires test infrastructure
- Best for production environments

## Conclusion

**Current State**: No formal testing ❌

**Recommended Approach**: Start with linting and syntax checks, then add Molecule for key roles

**Priority**: High - Testing prevents production issues and increases confidence

**Next Steps**: 
1. Add ansible-lint and yamllint
2. Create configuration files
3. Add to pre-commit hook
4. Fix existing issues
5. Document in README
