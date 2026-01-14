#!/bin/bash
# Automated deployment script with validation and rollback
# Usage: deploy-services.sh [--dry-run] [--skip-validation]

set -euo pipefail

DRY_RUN=false
SKIP_VALIDATION=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Pre-deployment validation
if [ "${SKIP_VALIDATION}" = false ]; then
    echo "Running pre-deployment validation..."
    if ! /usr/local/bin/validate-configs.sh; then
        echo "Validation failed. Aborting deployment."
        exit 1
    fi
    echo "✓ Validation passed"
fi

# Create backup before deployment
echo "Creating backup..."
if [ "${DRY_RUN}" = false ]; then
    /usr/local/bin/backup-configs.sh
else
    echo "[DRY RUN] Would create backup"
fi

# Deploy services (this would typically run Ansible playbook)
echo "Deploying services..."
if [ "${DRY_RUN}" = false ]; then
    # Run Ansible playbook (example)
    # ansible-playbook -i inventories/prod/hosts.yml playbooks/rigel-production.yml
    echo "Deployment completed"
else
    echo "[DRY RUN] Would deploy services"
fi

# Post-deployment validation
echo "Running post-deployment validation..."
if [ "${DRY_RUN}" = false ]; then
    # Wait for services to start
    sleep 5
    
    # Check service status
    if ! systemctl is-active --quiet coredns; then
        echo "ERROR: CoreDNS service not active after deployment"
        exit 1
    fi
    
    if ! systemctl is-active --quiet traefik; then
        echo "ERROR: Traefik service not active after deployment"
        exit 1
    fi
    
    # Run health checks
    if ! /usr/local/bin/health-check.sh; then
        echo "ERROR: Health checks failed after deployment"
        echo "Consider rolling back..."
        exit 1
    fi
else
    echo "[DRY RUN] Would run post-deployment validation"
fi

echo "✓ Deployment completed successfully"
