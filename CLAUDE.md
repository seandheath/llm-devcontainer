# CLAUDE.md — nix-sandbox

## Project Overview

Container-based Claude Code development environment using Nix. Provides isolated, reproducible environments with security hardening.

## Architecture

```
flake.nix                     # Main entry point
├── lib/mkDevContainer.nix    # Core: generates podman run scripts
├── lib/egress-proxy.nix      # Stub: future network filtering
├── packages/base-image.nix   # Nix-built OCI base layers
├── container/
│   ├── Containerfile         # Stage 2: npm install claude-code
│   ├── entrypoint.sh         # Init: credentials, nix store verification
│   └── zshrc                 # Shell config
├── templates/default/        # User project template
└── apps/test.nix             # Test suite
```

## Key Design Decisions

1. **Two-stage build**: Nix builds base image, Containerfile adds npm packages (avoids nix sandbox network issues)

2. **Preemptive credential symlinks**: entrypoint.sh creates symlinks to auth volume BEFORE Claude runs

3. **Host /nix/store sharing**: `-v /nix/store:/nix/store:ro` avoids re-downloading packages

4. **Rootless podman**: `--userns=keep-id` maps UIDs, no root required

## Development Commands

```bash
make build    # Two-stage container build
make test     # Run test suite
make lint     # Shellcheck + nil
make fmt      # nixfmt
```

## Code Style

- Nix: nixfmt, nil for LSP
- Shell: shellcheck, shfmt
- Comments: Explain why, reference docs/RFCs

## Testing

```bash
nix run .#test
```

Tests verify: container starts, nix works, claude installed, read-only filesystem, workspace mounts.

## Security Model

- `--read-only` root filesystem
- `--cap-drop=ALL`
- `--security-opt=no-new-privileges`
- tmpfs for writable paths
- Named volumes for credential persistence only
