# Testing Installation Guide (Containerized)

**No host installation required!** All testing tools run in Docker containers.

## Quick Start

Just run the scripts - they'll build and use containers automatically:

```bash
# Run all tests
./scripts/run-all-tests.sh

# Run specific tests
./scripts/run-linting.sh
./scripts/run-molecule-tests.sh
./scripts/validate-playbooks.sh
```

## Requirements

**Only Docker is required** - no Python, pip, or other tools needed on your host!

- **Docker Desktop** (macOS/Windows) or **Docker Engine** (Linux)
- Docker must be running
- For Molecule tests: Docker socket must be accessible (`/var/run/docker.sock`)

That's it! No Python, no pip, no virtual environments, no host pollution.

## How It Works

All testing scripts automatically:
1. Build a testing container image (`intergalactic-ansible-testing:latest`)
2. Run tests inside the container
3. Mount your code directory
4. Clean up after themselves

**No host installation** - everything runs in containers!

## Testing Scripts

### Linting

```bash
# Run all linting checks
./scripts/run-linting.sh

# Run specific linter
./scripts/run-linting.sh ansible-lint
./scripts/run-linting.sh yamllint
```

**What it does**:
- Builds testing container (if needed)
- Runs `ansible-lint` on all Ansible files
- Runs `yamllint` on all YAML files
- Reports errors and warnings

### Syntax Validation

```bash
./scripts/validate-playbooks.sh
```

**What it does**:
- Builds testing container (if needed)
- Validates all playbook syntax
- Checks for common issues

### Molecule Tests

```bash
# Test all roles
./scripts/run-molecule-tests.sh

# Test specific role
./scripts/run-molecule-tests.sh docker_deploy
```

**What it does**:
- Builds testing container (if needed)
- Runs Molecule tests for roles with test infrastructure
- Tests role idempotency and convergence
- Requires Docker socket access (for Docker-in-Docker)

**Available roles**:
- `docker_deploy`
- `internal_dns`
- `edge_ingress`
- `firewall_nftables`

### All Tests

```bash
# Run everything
./scripts/run-all-tests.sh

# Skip specific phases
./scripts/run-all-tests.sh --skip-molecule
```

## Manual Container Usage

If you want to run tests manually in the container:

### Build the Image

```bash
docker build -t intergalactic-ansible-testing:latest \
  -f docker/ansible-runner/Dockerfile.testing \
  docker/ansible-runner
```

### Run Linting

```bash
docker run --rm -v $(pwd):/repo \
  intergalactic-ansible-testing:latest \
  ansible-lint ansible/

docker run --rm -v $(pwd):/repo \
  intergalactic-ansible-testing:latest \
  yamllint -c .yamllint ansible/
```

### Run Syntax Check

```bash
docker run --rm -v $(pwd):/repo \
  intergalactic-ansible-testing:latest \
  ansible-playbook --syntax-check ansible/playbooks/rigel-production.yml
```

### Run Molecule (Requires Docker Socket)

```bash
docker run --rm -it \
  -v $(pwd):/repo \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w /repo/ansible/roles/docker_deploy \
  intergalactic-ansible-testing:latest \
  molecule test
```

### Run Testinfra (Requires SSH Keys)

```bash
docker run --rm -it \
  -v $(pwd):/repo \
  -v $HOME/.ssh:/root/.ssh:ro \
  intergalactic-ansible-testing:latest \
  pytest tests/testinfra/ \
    --hosts=ansible://rigel \
    --ansible-inventory=ansible/inventories/prod/hosts.yml \
    -v
```

## Troubleshooting

### Docker Not Running

**macOS/Windows**: Start Docker Desktop

**Linux**: 
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

### Docker Socket Not Found

**macOS**: Docker Desktop must be running

**Linux**: Ensure Docker socket is accessible:
```bash
ls -l /var/run/docker.sock
# Should show: srw-rw---- 1 root docker
```

If you get permission errors:
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

### Container Build Fails

Check Docker has enough resources:
- Memory: At least 2GB available
- Disk: At least 5GB free space

### Molecule Tests Fail

**Docker-in-Docker issues**:
- Ensure Docker Desktop is running (macOS/Windows)
- Check Docker socket is accessible: `ls -l /var/run/docker.sock`
- Verify Docker has enough resources

**Permission errors**:
- On Linux, add user to docker group: `sudo usermod -aG docker $USER`
- Restart Docker or log out/in

### Testinfra Connection Issues

**SSH keys not found**:
- Ensure SSH keys are in `~/.ssh/`
- Check keys have correct permissions: `chmod 600 ~/.ssh/id_*`

**Host unreachable**:
- Verify hosts are accessible: `ssh ansible@rigel`
- Check inventory file is correct
- Ensure Tailscale is connected (for production hosts)

## Benefits

✅ **No host installation** - Keep your system clean  
✅ **Reproducible** - Same environment everywhere  
✅ **Isolated** - No conflicts with other tools  
✅ **Easy updates** - Just rebuild the container  
✅ **CI/CD ready** - Containers are standard in CI/CD  
✅ **Consistent** - Same tools and versions for everyone  

## What's in the Container?

The testing container includes:
- **Ansible** 10.5.0
- **ansible-lint** >= 6.22.0
- **yamllint** >= 1.35.0
- **molecule** >= 5.0.0
- **molecule-plugins[docker]** >= 2.0.0
- **testinfra** >= 9.0.0
- **pytest** >= 7.0.0
- **pre-commit** >= 3.0.0
- **Docker** (for Molecule Docker driver)

All tools are pre-installed and ready to use!

## CI/CD Integration

The containerized approach works perfectly in CI/CD:

```yaml
# Example GitHub Actions
- name: Run linting
  run: ./scripts/run-linting.sh

- name: Validate playbooks
  run: ./scripts/validate-playbooks.sh

- name: Run Molecule tests
  run: ./scripts/run-molecule-tests.sh
```

No setup required - just run the scripts!

## Next Steps

1. **Run tests**: `./scripts/run-all-tests.sh`
2. **Set up pre-commit**: See main README for pre-commit setup
3. **Integrate with CI/CD**: Add test steps to your pipeline
4. **Read testing docs**: `TESTING_STRATEGY.md` for detailed strategy

## Support

For issues or questions:
- Check `TESTING_STRATEGY.md` for detailed testing strategy
- Review `scripts/README.md` for script documentation
- See `tests/testinfra/README.md` for Testinfra usage
