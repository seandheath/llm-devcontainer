#!/bin/bash
# Container entrypoint script for llm-devcontainer
#
# Responsibilities:
# 1. Verify /nix/store is properly mounted
# 2. Set up credential symlinks to persistent volume
# 3. Initialize environment
# 4. Execute requested command or shell
#
# The auth volume (/auth) persists Claude credentials between container runs.
# We create symlinks BEFORE Claude runs so credential writes go to the volume.

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

    # Quick sanity check - verify a known path exists
    if [[ ! -x /bin/zsh ]] && [[ ! -x /usr/bin/zsh ]]; then
        # zsh might be in nix store path, check PATH
        if ! command -v zsh &>/dev/null; then
            log_warn "zsh not found in PATH, shell may not work correctly"
        fi
    fi

    log_info "Nix store verified"
}

# Set up authentication credential symlinks
# This runs BEFORE Claude to ensure credentials write to persistent volume
setup_credentials() {
    local auth_volume="/auth"
    local claude_dir="$HOME/.claude"

    # Create auth volume directories if they don't exist
    # These will be on the persistent volume
    if [[ -d "$auth_volume" ]]; then
        log_info "Setting up credential symlinks to auth volume"

        # Ensure auth volume has correct structure
        mkdir -p "$auth_volume/.claude"

        # Key files that Claude Code uses for authentication:
        # - credentials.json: API key storage
        # - settings.json: User preferences (may include auth state)
        # - .credentials: OAuth tokens (if using OAuth flow)
        local auth_files=(
            "credentials.json"
            "settings.json"
            ".credentials"
            "statsig_session_id"
            "claude_session_key"
        )

        # Ensure ~/.claude exists (may be tmpfs)
        mkdir -p "$claude_dir"

        for file in "${auth_files[@]}"; do
            local volume_path="$auth_volume/.claude/$file"
            local home_path="$claude_dir/$file"

            # Create empty file in volume if doesn't exist (so symlink target exists)
            if [[ ! -e "$volume_path" ]]; then
                touch "$volume_path"
            fi

            # Remove existing file/symlink and create new symlink
            rm -f "$home_path"
            ln -sf "$volume_path" "$home_path"
        done

        log_info "Credentials linked to persistent volume"
    else
        log_warn "No auth volume mounted at $auth_volume"
        log_warn "Credentials will not persist between container runs"
        log_warn "Mount with: -v claude-auth-\${PROJECT}:/auth"
    fi
}

# Set up host config mounts (read-only)
# These are mounted by mkDevContainer.nix if they exist on host
setup_host_configs() {
    local claude_dir="$HOME/.claude"

    mkdir -p "$claude_dir"

    # Global CLAUDE.md from host (read-only reference)
    if [[ -f "/host-config/CLAUDE.md" ]]; then
        # If not already symlinked to auth volume, link to host config
        if [[ ! -L "$claude_dir/CLAUDE.md" ]]; then
            ln -sf "/host-config/CLAUDE.md" "$claude_dir/CLAUDE.md"
            log_info "Linked host CLAUDE.md"
        fi
    fi

    # Host settings.json (read-only reference for defaults)
    # Note: writable settings.json is symlinked in setup_credentials
    if [[ -f "/host-config/settings.json" ]] && [[ ! -L "$claude_dir/settings.json" ]]; then
        log_info "Host settings.json available at /host-config/settings.json"
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

# Fix permissions on writable directories
# Needed because --userns=keep-id maps host UID but directories may have wrong owner
fix_permissions() {
    local dirs=(
        "$HOME/.cache"
        "$HOME/.local"
        "$HOME/.npm"
        "$HOME/.npm-global"
        "$HOME/.config"
        "$HOME/.claude"
    )

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]] && [[ -w "$dir" ]]; then
            # Directory exists and is writable, good
            :
        elif [[ -d "$dir" ]]; then
            log_warn "Directory $dir exists but may not be writable"
        fi
    done
}

# Main entrypoint logic
main() {
    log_info "Initializing llm-devcontainer container"

    verify_nix_store
    setup_credentials
    setup_host_configs
    fix_permissions
    setup_direnv

    log_info "Container initialized"

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
