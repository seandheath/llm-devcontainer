#!/bin/bash
# Container entrypoint script for llm-devcontainer
#
# Responsibilities:
# 1. Verify /nix/store is properly mounted
# 2. Set up home directory (tmpfs at runtime, dotfiles from /etc/skel)
# 3. Bootstrap credentials from host to persistent volume
# 4. Initialize direnv if present
# 5. Execute requested command or shell
#
# Home directory:
# - /home/developer is tmpfs at runtime (writable but not persistent)
# - Dotfiles stored in /etc/skel, copied on startup
# - ~/.claude is a persistent volume mounted on top
#
# Credential flow:
# - Host ~/.claude mounted read-only at /host-claude
# - Container ~/.claude is a persistent volume (per-project)
# - On first run, credentials copied from host to volume

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
# Home is tmpfs at runtime, so we copy dotfiles from /etc/skel
# and create necessary directories
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

# Bootstrap credentials from host if not present in volume
# Host ~/.claude is mounted read-only at /host-claude
# Container's ~/.claude is a persistent volume
setup_credentials() {
    local host_claude="/host-claude"
    local container_claude="$HOME/.claude"

    # Skip if host config not mounted
    if [[ ! -d "$host_claude" ]]; then
        log_warn "Host ~/.claude not mounted at /host-claude"
        log_warn "Run 'claude login' inside container to authenticate"
        return
    fi

    # Copy credentials if not already present
    if [[ -f "$host_claude/.credentials.json" ]] && [[ ! -f "$container_claude/.credentials.json" ]]; then
        cp "$host_claude/.credentials.json" "$container_claude/.credentials.json"
        log_info "Copied credentials from host"
    fi

    # Copy CLAUDE.md if not present (user's global instructions)
    if [[ -f "$host_claude/CLAUDE.md" ]] && [[ ! -f "$container_claude/CLAUDE.md" ]]; then
        cp "$host_claude/CLAUDE.md" "$container_claude/CLAUDE.md"
        log_info "Copied CLAUDE.md from host"
    fi

    # Copy settings.json if not present
    if [[ -f "$host_claude/settings.json" ]] && [[ ! -f "$container_claude/settings.json" ]]; then
        cp "$host_claude/settings.json" "$container_claude/settings.json"
        log_info "Copied settings.json from host"
    fi
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
    setup_home
    setup_credentials
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
