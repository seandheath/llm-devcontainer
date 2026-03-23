#!/bin/bash
# Container entrypoint script for llm-devcontainer
#
# Responsibilities:
# 1. Verify /nix/store is properly mounted
# 2. Initialize direnv if present
# 3. Execute requested command or shell
#
# Credentials are handled via direct volume mount at ~/.claude by mkDevContainer.nix

set -euo pipefail

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[entrypoint]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[entrypoint]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[entrypoint]${NC} $*" >&2
}

# Verify Nix store is mounted
verify_nix_store() {
    if [[ ! -d /nix/store ]]; then
        log_error "FATAL: /nix/store is not mounted"
        log_error "Ensure container is started with: -v /nix/store:/nix/store:ro"
        exit 1
    fi

    # Quick sanity check - verify zsh is available
    if ! command -v zsh &>/dev/null; then
        log_warn "zsh not found in PATH, shell may not work correctly"
    fi

    log_info "Nix store verified"
}

# Initialize direnv if present
setup_direnv() {
    if command -v direnv &>/dev/null; then
        # Hook direnv into shells
        eval "$(direnv hook bash)" 2>/dev/null || true

        # Allow workspace .envrc if present
        if [[ -f /workspace/.envrc ]]; then
            log_info "Found .envrc in workspace, allowing direnv"
            direnv allow /workspace 2>/dev/null || true
        fi
    fi
}

# Main entrypoint logic
main() {
    log_info "Initializing llm-devcontainer"

    verify_nix_store
    setup_direnv

    log_info "Container ready"

    # Execute command or default shell
    if [[ $# -eq 0 ]]; then
        log_info "Starting interactive shell"
        exec /bin/zsh -l
    else
        log_info "Executing: $*"
        exec "$@"
    fi
}

main "$@"
