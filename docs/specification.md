# llm-devcontainer Specification

## Purpose

Provide a secure, reproducible container environment for running Claude Code in development projects.

## Goals

1. **Security**: Minimize attack surface through containerization, capability dropping, and read-only filesystems
2. **Reproducibility**: Use Nix for deterministic base image builds
3. **Usability**: Simple `nix run .#dev` or `nix run .#claude` from any project
4. **Portability**: Standalone flake, no host configuration changes required
5. **Compatibility**: Support hardware development with USB passthrough

## Non-Goals

- Full VM isolation (containers share kernel with host)
- Windows/macOS support (Linux only, uses Podman)
- GUI applications (CLI only)

## Architecture

### Container Build (Two-Stage)

**Stage 1: Nix Base Image**
- Built with `dockerTools.buildLayeredImage`
- Contains: nix, nodejs, git, zsh, direnv, neovim, curl, coreutils
- Deterministic, cached in Nix store
- Output: OCI image tarball

**Stage 2: Containerfile**
- Extends Nix base image
- Runs `npm install -g @anthropic-ai/claude-code`
- Copies entrypoint and config files
- Output: Final container image

### Runtime Security

| Control | Implementation |
|---------|----------------|
| Read-only root | `--read-only` |
| No capabilities | `--cap-drop=ALL` |
| No privilege escalation | `--security-opt=no-new-privileges` |
| User isolation | `--userns=keep-id` |
| Network isolation | `--network=pasta` (or slirp4netns) |

### Volume Mounts

| Mount | Purpose | Mode |
|-------|---------|------|
| `/nix/store` | Nix packages | ro |
| `/<project-name>` | Project directory (matches host folder name) | rw |
| `/home/developer` | Ephemeral home directory | rw |
| `/home/developer/.claude` | Credential persistence (named volume) | rw |

### Credential Management

Claude stores credentials in `~/.claude/`. In the container:
1. `/home/developer` is an ephemeral volume (fresh each session)
2. `~/.claude` is a named Podman volume mounted on top (persistent)
3. Credentials persist across container restarts

### USB Passthrough

For hardware development:
1. User specifies vendor:product patterns in config
2. At container start, script scans `/sys/bus/usb/devices/`
3. Matching devices get `--device=/dev/X` flags added to podman run

## Interfaces

### mkDevContainer

```nix
mkDevContainer {
  name: string;           # Project name
  projectPath: string;    # Absolute path to project
  image?: string;         # Container image (default: "llm-devcontainer:latest")
  enableUSB?: bool;       # Enable USB passthrough (default: false)
  usbDevices?: [string];  # Vendor:product patterns
  extraMounts?: [{host, container, opts}];
  extraEnv?: {string: string};
  networkMode?: string;   # "pasta" | "slirp4netns" | "host"
  extraArgs?: [string];   # Additional podman args
}
```

Returns: `{ shell, claude, detached, dev, devHw, meta }`

### mkEgressConfig (Stub)

```nix
mkEgressConfig {
  allowedDomains?: [string];  # Domain whitelist
  blockByDefault?: bool;      # Default: true
  logBlocked?: bool;          # Default: true
}
```

Returns: Configuration for future egress proxy.

## Future Work

- **Egress filtering**: Implement domain whitelisting via mitmproxy or DNS filtering
- **Multi-architecture**: Support aarch64 builds
- **Remote execution**: Run containers on remote hosts
- **IDE integration**: VS Code devcontainer support
