# Containerized Testing - Quick Reference

**All testing runs in Docker containers - no host installation required!**

## Quick Start

```bash
# Run all tests (containers built automatically)
./scripts/run-all-tests.sh

# Run specific tests
./scripts/run-linting.sh
./scripts/validate-playbooks.sh
./scripts/run-molecule-tests.sh
```

## Requirements

**Only Docker is needed:**
- Docker Desktop (macOS/Windows) or Docker Engine (Linux)
- Docker must be running
- For Molecule: Docker socket accessible (`/var/run/docker.sock`)

**No Python, pip, virtual environments, or other tools needed!**

## What's Containerized?

✅ **ansible-lint** - Ansible code quality  
✅ **yamllint** - YAML syntax validation  
✅ **ansible-playbook --syntax-check** - Playbook validation  
✅ **molecule** - Role testing  
✅ **testinfra** - Production verification  

## How It Works

1. Scripts automatically build `intergalactic-ansible-testing:latest` container
2. Run tests inside the container
3. Mount your code directory
4. Clean up after themselves

## Container Image

Built from: `docker/ansible-runner/Dockerfile.testing`

Includes:
- Ansible 10.5.0
- ansible-lint >= 6.22.0
- yamllint >= 1.35.0
- molecule >= 5.0.0
- molecule-plugins[docker] >= 2.0.0
- testinfra >= 9.0.0
- pytest >= 7.0.0
- pre-commit >= 3.0.0
- Docker (for Molecule Docker driver)

## Benefits

✅ **No host pollution** - Keep your system clean  
✅ **Reproducible** - Same environment everywhere  
✅ **Isolated** - No conflicts with other tools  
✅ **Easy updates** - Just rebuild the container  
✅ **CI/CD ready** - Containers are standard  

## Manual Container Usage

```bash
# Build image
docker build -t intergalactic-ansible-testing:latest \
  -f docker/ansible-runner/Dockerfile.testing \
  docker/ansible-runner

# Run linting
docker run --rm -v $(pwd):/repo \
  intergalactic-ansible-testing:latest \
  ansible-lint ansible/

# Run Molecule (requires Docker socket)
docker run --rm -it \
  -v $(pwd):/repo \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w /repo/ansible/roles/docker_deploy \
  intergalactic-ansible-testing:latest \
  molecule test
```

## Documentation

- **`TESTING_INSTALLATION.md`** - Detailed containerized installation guide
- **`TESTING_STRATEGY.md`** - Testing strategy and recommendations
- **`scripts/README.md`** - Script documentation

## Troubleshooting

**Docker not running**: Start Docker Desktop (macOS/Windows) or `sudo systemctl start docker` (Linux)

**Docker socket not found**: Ensure Docker Desktop is running (macOS) or Docker socket is accessible (Linux)

**Permission errors**: Add user to docker group: `sudo usermod -aG docker $USER` (Linux)

See `TESTING_INSTALLATION.md` for detailed troubleshooting.
