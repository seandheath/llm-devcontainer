#!/bin/bash
# Container entrypoint script for llm-devcontainer
#
# Responsibilities:
# 1. Verify /nix/store is properly mounted
# 2. Set up home directory (volume at runtime, dotfiles from /etc/skel)
# 3. Execute requested command or shell
#
# Volume layout:
# - /home/developer is a volume (writable, persists per-project)
# - ~/.claude is a separate volume for credential persistence

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

# Set up home directory
# Home is a volume, so on first run we copy dotfiles from /etc/skel
setup_home() {
    # Copy dotfiles from /etc/skel if not present
    if [[ -f /etc/skel/.zshrc ]] && [[ ! -f "$HOME/.zshrc" ]]; then
        cp /etc/skel/.zshrc "$HOME/.zshrc"
    fi

    # Create directories that tools expect
    mkdir -p "$HOME/.cache"
    mkdir -p "$HOME/.local/share"
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.npm"
    mkdir -p "$HOME/.npm-global"
    mkdir -p "$HOME/.config"
}


# Main entrypoint logic
main() {
    log_info "Initializing llm-devcontainer"

    verify_nix_store
    setup_home

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
