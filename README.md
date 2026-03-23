# llm-devcontainer

Container-based Claude Code development environment with Nix.

## Overview

llm-devcontainer provides isolated, reproducible development environments for Claude Code. It uses Podman containers with Nix for dependency management, combining the security of containerization with the reproducibility of Nix.

**Key features:**
- Rootless containers with minimal attack surface
- Read-only root filesystem
- Persistent credential storage
- Host Nix store sharing (no re-downloading packages)
- USB device passthrough for hardware development

## Quick Start

```bash
# Build the container image
make build

# Run Claude Code in a containerized environment
make claude

# Or enter an interactive shell
make container-shell
```

## Installation

llm-devcontainer is a standalone Nix flake. No host system changes required.

### Prerequisites

- Nix with flakes enabled
- Podman (rootless)

### Using in Your Project

1. Initialize from template:
   ```bash
   nix flake init -t github:seandheath/llm-devcontainer
   ```

2. Edit `flake.nix` to configure your project name and options

3. Run:
   ```bash
   nix run .#dev     # Interactive shell
   nix run .#claude  # Claude Code
   ```

## Architecture

### Two-Stage Build

1. **Stage 1 (Nix):** `dockerTools.buildLayeredImage` creates the base image with all Nix packages (nodejs, git, zsh, direnv, etc.)

2. **Stage 2 (Containerfile):** `npm install -g @anthropic-ai/claude-code` installs Claude Code on top of the Nix base

This avoids Nix sandbox network restrictions while keeping most of the image deterministic.

### Security Model

- **Read-only root:** `--read-only` flag prevents modifications to system files
- **No capabilities:** `--cap-drop=ALL` removes all Linux capabilities
- **No privilege escalation:** `--security-opt=no-new-privileges`
- **User namespace isolation:** `--userns=keep-id` maps container UID to host UID
- **Minimal writable paths:** Only `/tmp`, `/var`, `~/.cache`, `~/.local`, and workspace are writable (via tmpfs or bind mounts)

### Credential Persistence

Claude credentials are stored in a named Podman volume (`claude-auth-${project}`). The entrypoint script creates symlinks from `~/.claude/` to this volume before Claude runs, ensuring credentials persist across container restarts.

## Configuration

### mkDevContainer Options

```nix
containerLib.mkDevContainer {
  name = "my-project";           # Project name (used for volume naming)
  projectPath = toString ./.;    # Path to project directory

  # Optional settings
  image = "llm-devcontainer:latest";  # Container image
  enableUSB = false;             # USB device passthrough
  usbDevices = [];               # Vendor:product patterns ["0483:374b"]
  extraMounts = [];              # Additional volume mounts
  extraEnv = {};                 # Environment variables
  networkMode = "pasta";         # Network: pasta, slirp4netns, host
  extraArgs = [];                # Additional podman arguments
}
```

### USB Device Passthrough

For hardware development (embedded, microcontrollers):

```nix
containerLib.mkDevContainer {
  name = "firmware-project";
  projectPath = toString ./.;
  enableUSB = true;
  usbDevices = [
    "0483:374b"  # ST-Link V2.1
    "1a86:7523"  # CH340 USB-Serial
    "10c4:ea60"  # CP2102
  ];
}
```

## Development

```bash
# Enter dev shell
nix develop

# Build and test
make build
make test

# Lint and format
make lint
make fmt
```

## Files

| Path | Description |
|------|-------------|
| `flake.nix` | Main flake with packages, apps, templates |
| `lib/mkDevContainer.nix` | Core container generation function |
| `lib/egress-proxy.nix` | Egress filtering (stub) |
| `packages/base-image.nix` | Nix-built OCI base image |
| `container/Containerfile` | Stage 2: Claude Code installation |
| `container/entrypoint.sh` | Container initialization script |
| `container/zshrc` | Default shell configuration |
| `templates/default/` | Project template |
| `apps/test.nix` | Test suite |

## Troubleshooting

### "pasta" network mode not available

Older Podman versions may not support pasta. Use slirp4netns:

```nix
networkMode = "slirp4netns";
```

### Permission denied on workspace files

Ensure Podman is configured for rootless operation with `--userns=keep-id`. The container UID should map to your host UID.

### Claude credentials not persisting

Verify the auth volume exists:
```bash
podman volume ls | grep claude-auth
```

If missing, it will be created on next run.

## License

MIT
