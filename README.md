# llm-devcontainer

Container-based Claude Code development environment with Nix.

## Overview

llm-devcontainer provides isolated, reproducible development environments for Claude Code. It uses Podman containers with Nix for dependency management, combining the security of containerization with the reproducibility of Nix.

**Key features:**
- Rootless containers with minimal attack surface
- Read-only root filesystem
- Persistent credential storage
- Host Nix store sharing (no re-downloading packages)
- Dynamic workspace path (`/<project-name>` inside container matches host folder)

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

Add this function to your shell config (`~/.bashrc`, `~/.zshrc`, or NixOS config):

```bash
new-project() {
    local name="${1:?usage: new-project <project-name>}"
    mkdir -p "$name" && cd "$name" && nix flake init -t github:seandheath/llm-devcontainer --refresh

    # Set project name in flake.nix
    sed -i "s/projectName = \"my-project\"/projectName = \"$name\"/" flake.nix

    # Build container image if needed
    if ! podman image exists llm-devcontainer:latest; then
        nix run github:seandheath/llm-devcontainer#build
    fi

    # Pre-build shell/claude apps to avoid lag on first run
    nix build .#shell .#claude --no-link
}
```

For NixOS, escape `${` as `''${`:

```nix
programs.bash.initExtra = ''
  new-project() {
      local name="''${1:?usage: new-project <project-name>}"
      mkdir -p "$name" && cd "$name" && nix flake init -t github:seandheath/llm-devcontainer --refresh
      sed -i "s/projectName = \"my-project\"/projectName = \"$name\"/" flake.nix
      if ! podman image exists llm-devcontainer:latest; then
          nix run github:seandheath/llm-devcontainer#build
      fi
      nix build .#shell .#claude --no-link
  }
'';
```

Then create and use a project:

```bash
new-project myapp
nix develop
claude
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
- **Minimal writable paths:** Only `/tmp`, `/var`, `/run`, home directory, and project workspace are writable (via tmpfs or volumes)

### Credential Persistence

Claude credentials are stored in a named Podman volume (`claude-auth-${project}`) mounted directly at `~/.claude`. This volume persists across container restarts while keeping the rest of the home directory ephemeral.

### Dynamic Workspace

The project directory is mounted at `/<project-name>` inside the container, matching the host folder name. This makes paths in Claude's output directly usable on the host system.

## Configuration

### mkDevContainer Options

```nix
containerLib.mkDevContainer {
  name = "my-project";           # Project name (used for volume naming)
  projectPath = toString ./.;    # Path to project directory

  # Optional settings
  image = "llm-devcontainer:latest";  # Container image
  extraMounts = [];              # Additional volume mounts
  extraEnv = {};                 # Environment variables
  networkMode = "pasta";         # Network: pasta, slirp4netns, host
  extraArgs = [];                # Additional podman arguments
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
