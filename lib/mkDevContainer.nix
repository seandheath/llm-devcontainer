# mkDevContainer - Generate podman run scripts for development containers
#
# This is the core function of nix-sandbox. It takes a project configuration
# and produces shell scripts that launch properly-configured containers.
#
# Security model:
# - Read-only root filesystem (--read-only)
# - No new privileges (--security-opt no-new-privileges)
# - Drop all capabilities (--cap-drop ALL)
# - User namespace isolation (--userns=keep-id)
# - Minimal writable paths via tmpfs
# - Persistent auth volume for credentials
#
# References:
# - https://docs.podman.io/en/latest/markdown/podman-run.1.html
# - https://man.archlinux.org/man/slirp4netns.1

{ pkgs
, lib ? pkgs.lib
}:

let
  # Helper to generate conditional mount flags
  # Returns empty string if path doesn't exist
  conditionalMount = hostPath: containerPath: opts:
    ''
      if [[ -e "${hostPath}" ]]; then
        MOUNTS+=("-v" "${hostPath}:${containerPath}:${opts}")
      fi
    '';

  # Helper to detect USB devices matching vendor:product patterns
  # Returns --device flags for each matching device
  usbDeviceDetection = vendorProductPairs: ''
    # USB device detection
    # Scans /sys/bus/usb/devices/ for matching vendor:product IDs
    detect_usb_devices() {
      local devices=()
      for dev in /sys/bus/usb/devices/*/; do
        [[ -f "$dev/idVendor" ]] || continue
        [[ -f "$dev/idProduct" ]] || continue

        local vendor=$(cat "$dev/idVendor" 2>/dev/null)
        local product=$(cat "$dev/idProduct" 2>/dev/null)
        local vid_pid="$vendor:$product"

        # Check against known device patterns
        case "$vid_pid" in
          ${lib.concatMapStringsSep "|" (p: "\"${p}\"") vendorProductPairs})
            # Find the /dev node for this USB device
            for tty in "$dev"/tty*/; do
              [[ -d "$tty" ]] || continue
              local devname=$(basename "$tty")
              if [[ -c "/dev/$devname" ]]; then
                devices+=("--device=/dev/$devname")
              fi
            done
            # Check for generic USB device nodes
            local devnum=$(cat "$dev/devnum" 2>/dev/null)
            local busnum=$(cat "$dev/busnum" 2>/dev/null)
            if [[ -n "$devnum" && -n "$busnum" ]]; then
              local usbdev="/dev/bus/usb/$(printf '%03d' "$busnum")/$(printf '%03d' "$devnum")"
              if [[ -c "$usbdev" ]]; then
                devices+=("--device=$usbdev")
              fi
            fi
            ;;
        esac
      done
      echo "''${devices[@]}"
    }
  '';

in
{
  # Main function to create a development container configuration
  #
  # Arguments:
  #   name          - Project name (used for auth volume naming)
  #   projectPath   - Absolute path to project directory on host
  #   image         - Container image name (default: nix-sandbox:latest)
  #   enableUSB     - Enable USB device passthrough (default: false)
  #   usbDevices    - List of vendor:product patterns (e.g., ["1234:5678"])
  #   extraMounts   - Additional volume mounts [{host, container, opts}]
  #   extraEnv      - Additional environment variables {NAME = "value"}
  #   networkMode   - Network mode: "pasta", "slirp4netns", "host" (default: "pasta")
  #   extraArgs     - Additional podman arguments (list of strings)
  #
  # Returns:
  #   Attribute set with shell scripts for different use cases
  mkDevContainer =
    { name
    , projectPath
    , image ? "nix-sandbox:latest"
    , enableUSB ? false
    , usbDevices ? []
    , extraMounts ? []
    , extraEnv ? {}
    , networkMode ? "pasta"
    , extraArgs ? []
    }:

    let
      # Sanitize project name for use in volume names
      sanitizedName = lib.replaceStrings [" " "/" "\\"] ["-" "-" "-"] name;

      # Auth volume name - persists credentials across container runs
      authVolume = "claude-auth-${sanitizedName}";

      # Build environment variable flags
      envFlags = lib.concatStringsSep " " (
        lib.mapAttrsToList (k: v: ''-e "${k}=${v}"'') extraEnv
      );

      # Build extra mount flags
      extraMountFlags = lib.concatMapStringsSep " \\\n    " (m:
        ''-v "${m.host}:${m.container}:${m.opts}"''
      ) extraMounts;

      # Core podman run arguments shared by all variants
      coreArgs = ''
        # Image and basic options
        IMAGE="${image}"

        # Security options
        SECURITY=(
          "--read-only"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
        )

        # User namespace: map container UID to host UID
        # This ensures file permissions work correctly with bind mounts
        USERNS="--userns=keep-id"

        # Network mode
        # pasta is preferred (faster, more features)
        # slirp4netns is fallback for older Podman versions
        NETWORK="--network=${networkMode}"

        # Writable tmpfs mounts for runtime data
        # These paths need to be writable but don't persist
        TMPFS=(
          "--tmpfs=/tmp:rw,exec,nosuid,nodev,size=2g"
          "--tmpfs=/var:rw,noexec,nosuid,nodev,size=512m"
          "--tmpfs=/run:rw,noexec,nosuid,nodev,size=64m"
          "--tmpfs=/home/developer/.cache:rw,exec,nosuid,nodev,size=2g"
          "--tmpfs=/home/developer/.local:rw,exec,nosuid,nodev,size=1g"
          "--tmpfs=/home/developer/.npm:rw,exec,nosuid,nodev,size=512m"
          "--tmpfs=/home/developer/.claude:rw,noexec,nosuid,nodev,size=64m"
        )

        # Core volume mounts
        MOUNTS=(
          # Nix store - read-only, shared with host
          "-v" "/nix/store:/nix/store:ro"

          # Project workspace - read-write
          "-v" "${projectPath}:/workspace:rw"

          # Auth volume for credential persistence
          "-v" "${authVolume}:/auth:rw"
        )
      '';

      # Conditional host config mounts
      hostConfigMounts = ''
        # Host Claude config (global CLAUDE.md, etc.)
        # Only mount if files exist on host
        ${conditionalMount "$HOME/.claude/CLAUDE.md" "/host-config/CLAUDE.md" "ro"}
        ${conditionalMount "$HOME/.claude/settings.json" "/host-config/settings.json" "ro"}

        # SSH config for git operations (read-only)
        ${conditionalMount "$HOME/.ssh" "/home/developer/.ssh" "ro"}

        # Git config
        ${conditionalMount "$HOME/.gitconfig" "/home/developer/.gitconfig" "ro"}
        ${conditionalMount "$HOME/.config/git" "/home/developer/.config/git" "ro"}
      '';

      # USB device handling (only for dev-hw variant)
      usbHandling = if enableUSB then ''
        ${usbDeviceDetection usbDevices}

        # Detect and add USB devices
        USB_DEVICES=($(detect_usb_devices))
        if [[ ''${#USB_DEVICES[@]} -gt 0 ]]; then
          echo "[nix-sandbox] Found USB devices: ''${USB_DEVICES[*]}"
        fi
      '' else ''
        USB_DEVICES=()
      '';

      # Build the complete run script
      runScript = variant: pkgs.writeShellScript "nix-sandbox-${variant}" ''
        #!/usr/bin/env bash
        # nix-sandbox container launcher (${variant})
        # Generated by mkDevContainer.nix
        #
        # Project: ${name}
        # Workspace: ${projectPath}

        set -euo pipefail

        ${coreArgs}

        ${hostConfigMounts}

        ${usbHandling}

        # Extra mounts from configuration
        ${if extraMounts != [] then ''
        # Additional configured mounts
        MOUNTS+=(
          ${extraMountFlags}
        )
        '' else ""}

        # Extra environment variables
        ENV_VARS=(
          ${lib.concatStringsSep "\n          " (
            lib.mapAttrsToList (k: v: ''"-e" "${k}=${v}"'') extraEnv
          )}
        )

        # Extra podman arguments
        EXTRA_ARGS=(
          ${lib.concatMapStringsSep "\n          " (a: ''"${a}"'') extraArgs}
        )

        # Construct final podman command
        exec podman run \
          --rm \
          -it \
          --name "nix-sandbox-${sanitizedName}" \
          --hostname "nix-sandbox" \
          $USERNS \
          $NETWORK \
          "''${SECURITY[@]}" \
          "''${TMPFS[@]}" \
          "''${MOUNTS[@]}" \
          "''${USB_DEVICES[@]}" \
          "''${ENV_VARS[@]}" \
          "''${EXTRA_ARGS[@]}" \
          "$IMAGE" \
          "$@"
      '';

      # Script to start container in detached mode
      detachedScript = pkgs.writeShellScript "nix-sandbox-detached" ''
        #!/usr/bin/env bash
        # Start nix-sandbox in detached mode
        set -euo pipefail

        ${coreArgs}

        ${hostConfigMounts}

        ${usbHandling}

        ${if extraMounts != [] then ''
        MOUNTS+=(
          ${extraMountFlags}
        )
        '' else ""}

        ENV_VARS=(
          ${lib.concatStringsSep "\n          " (
            lib.mapAttrsToList (k: v: ''"-e" "${k}=${v}"'') extraEnv
          )}
        )

        EXTRA_ARGS=(
          ${lib.concatMapStringsSep "\n          " (a: ''"${a}"'') extraArgs}
        )

        CONTAINER_NAME="nix-sandbox-${sanitizedName}"

        # Check if already running
        if podman ps --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
          echo "[nix-sandbox] Container already running, attaching..."
          exec podman attach "$CONTAINER_NAME"
        fi

        # Start detached
        podman run \
          --rm \
          -d \
          --name "$CONTAINER_NAME" \
          --hostname "nix-sandbox" \
          $USERNS \
          $NETWORK \
          "''${SECURITY[@]}" \
          "''${TMPFS[@]}" \
          "''${MOUNTS[@]}" \
          "''${USB_DEVICES[@]}" \
          "''${ENV_VARS[@]}" \
          "''${EXTRA_ARGS[@]}" \
          "$IMAGE" \
          sleep infinity

        echo "[nix-sandbox] Container started: $CONTAINER_NAME"
        echo "[nix-sandbox] Attach with: podman attach $CONTAINER_NAME"
        echo "[nix-sandbox] Exec shell:  podman exec -it $CONTAINER_NAME /bin/zsh"
      '';

      # Script to run claude directly
      claudeScript = pkgs.writeShellScript "nix-sandbox-claude" ''
        #!/usr/bin/env bash
        # Run Claude Code directly in container
        set -euo pipefail

        ${coreArgs}

        ${hostConfigMounts}

        ${if extraMounts != [] then ''
        MOUNTS+=(
          ${extraMountFlags}
        )
        '' else ""}

        ENV_VARS=(
          ${lib.concatStringsSep "\n          " (
            lib.mapAttrsToList (k: v: ''"-e" "${k}=${v}"'') extraEnv
          )}
        )

        EXTRA_ARGS=(
          ${lib.concatMapStringsSep "\n          " (a: ''"${a}"'') extraArgs}
        )

        exec podman run \
          --rm \
          -it \
          --name "nix-sandbox-claude-${sanitizedName}" \
          --hostname "nix-sandbox" \
          $USERNS \
          $NETWORK \
          "''${SECURITY[@]}" \
          "''${TMPFS[@]}" \
          "''${MOUNTS[@]}" \
          "''${ENV_VARS[@]}" \
          "''${EXTRA_ARGS[@]}" \
          "$IMAGE" \
          claude "$@"
      '';

    in {
      # Interactive shell in container
      shell = runScript "shell";

      # Detached container with attach capability
      detached = detachedScript;

      # Direct claude invocation
      claude = claudeScript;

      # Development variant (same as shell for now)
      dev = runScript "dev";

      # Hardware development variant (USB passthrough)
      devHw = runScript "dev-hw";

      # Metadata for introspection
      meta = {
        inherit name projectPath image authVolume;
        inherit enableUSB usbDevices extraMounts extraEnv networkMode;
      };
    };
}
