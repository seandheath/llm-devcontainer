# nix-sandbox Makefile
#
# Standard targets for building, testing, and managing the project.

.PHONY: build test clean lint fmt check shell help

# Default target
.DEFAULT_GOAL := help

# Build the container image (two-stage)
build:
	nix run .#build

# Run the test suite
test:
	nix run .#test

# Clean build artifacts and container images
clean:
	rm -f result result-*
	podman rmi nix-sandbox:latest 2>/dev/null || true
	podman rmi nix-sandbox-base:latest 2>/dev/null || true

# Lint shell scripts and Nix files
lint:
	shellcheck container/entrypoint.sh
	find . -name '*.nix' -exec nil diagnostics {} \;

# Format Nix files
fmt:
	find . -name '*.nix' -exec nixfmt {} \;

# Run all checks (lint + test)
check: lint test

# Enter development shell
shell:
	nix develop

# Enter container shell (for testing)
container-shell:
	nix run .#shell

# Run claude in container
claude:
	nix run .#claude

# Verify flake
flake-check:
	nix flake check

# Show flake info
flake-info:
	nix flake show
	nix flake metadata

# Help
help:
	@echo "nix-sandbox - Container-based Claude Code development environment"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  build           Build the container image (two-stage)"
	@echo "  test            Run the test suite"
	@echo "  clean           Remove build artifacts and images"
	@echo "  lint            Lint shell scripts and Nix files"
	@echo "  fmt             Format Nix files"
	@echo "  check           Run lint and test"
	@echo "  shell           Enter development shell"
	@echo "  container-shell Enter container shell"
	@echo "  claude          Run Claude Code in container"
	@echo "  flake-check     Verify flake is valid"
	@echo "  flake-info      Show flake metadata"
	@echo "  help            Show this help"
