.PHONY: help diagnose check-dns check-traefik check-tailscale check-certs lint test deploy-traefik clean

# Default target
help:
	@echo "Intergalactic Infrastructure Management"
	@echo ""
	@echo "Diagnostic Commands:"
	@echo "  make diagnose          - Run all diagnostics (DNS, Traefik, Tailscale)"
	@echo "  make check-dns         - Check CoreDNS status and resolution"
	@echo "  make check-traefik     - Check Traefik status and certificates"
	@echo "  make check-certs       - Check ACME certificate status"
	@echo "  make check-tailscale   - Check Tailscale DNS configuration"
	@echo ""
	@echo "Deployment Commands:"
	@echo "  make deploy-traefik HOST=rigel  - Quick deploy Traefik configuration"
	@echo "  make deploy-dns HOST=rigel      - Quick deploy CoreDNS configuration"
	@echo ""
	@echo "Testing Commands:"
	@echo "  make lint              - Run all linting checks (ansible-lint, yamllint)"
	@echo "  make test              - Run all tests (lint + molecule)"
	@echo ""
	@echo "Cleanup Commands:"
	@echo "  make clean             - Remove temporary files and logs"

# Diagnostic targets
diagnose: check-tailscale check-dns check-traefik
	@echo "✅ All diagnostics complete"

check-dns:
	@./scripts/diagnose-dns-traefik.sh $(HOST)

check-traefik:
	@./scripts/diagnose-dns-traefik.sh $(HOST)

check-certs:
	@./scripts/check-acme-certificates.sh $(HOST)

check-tailscale:
	@./scripts/check-tailscale-dns.sh

# Deployment targets
deploy-traefik:
	@./scripts/quick-deploy-traefik.sh $(HOST)

deploy-dns:
	@./scripts/run-ansible.sh prod $(HOST) production --tags internal_dns

# Testing targets
lint:
	@./scripts/run-linting.sh

test: lint
	@./scripts/run-all-tests.sh

# Cleanup
clean:
	@echo "Cleaning temporary files..."
	@find . -type f -name "*.retry" -delete
	@find . -type f -name "*.pyc" -delete
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "✅ Cleanup complete"

# Set default host if not specified
HOST ?= rigel
