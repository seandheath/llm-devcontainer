{
  description = "llm-devcontainer: Container-based Claude Code development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Library functions available for all systems
      lib = {
        # Core container generation function
        # Import and call with pkgs to get the actual function
        mkDevContainer = import ./lib/mkDevContainer.nix;
      };

    in
    {
      # Export library functions
      inherit lib;

      # Templates for new projects
      templates = {
        default = {
          path = ./templates/default;
          description = "Basic llm-devcontainer project with Claude Code";
        };
      };

    } //
    # System-specific outputs
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        # Instantiate library with pkgs
        containerLib = lib.mkDevContainer { inherit pkgs; };

        # Base image package
        baseImage = import ./packages/base-image.nix {
          inherit pkgs;
          name = "llm-devcontainer-base";
          tag = "latest";
        };

      in {
        # Packages
        packages = {
          # Base OCI image (Nix-built layers)
          base-image = baseImage;

          # Alias
          default = baseImage;
        };

        # Development shell for working on llm-devcontainer itself
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Nix tools
            nil
            nixfmt

            # Container tools
            podman
            skopeo
            dive  # Image layer inspection

            # Shell tools
            shellcheck
            shfmt

            # Documentation
            mdbook
          ];

          shellHook = ''
            echo ""
            echo "llm-devcontainer development shell"
            echo "────────────────────────────"
            echo "Build base image:  nix build .#base-image"
            echo "Run tests:         nix run .#test"
            echo "Build container:   nix run .#build"
            echo ""
          '';
        };

        # Apps (executable scripts)
        apps = {
          # Two-stage build script
          build = {
            type = "app";
            program = toString (pkgs.writeShellScript "llm-devcontainer-build" ''
              set -euo pipefail

              # Use temp dir for build artifacts
              TMPDIR=$(mktemp -d)
              trap "rm -rf $TMPDIR" EXIT

              echo "[llm-devcontainer] Stage 1: Building Nix base image..."
              nix build ${self}#base-image --out-link "$TMPDIR/result"

              echo "[llm-devcontainer] Loading base image into podman..."
              podman load < "$TMPDIR/result"

              echo "[llm-devcontainer] Stage 2: Building final image with Claude Code..."
              podman build \
                -t llm-devcontainer:latest \
                -f ${self}/container/Containerfile \
                ${self}

              echo "[llm-devcontainer] Build complete!"
              echo ""
              echo "Image: llm-devcontainer:latest"
              echo "Run:   podman run --rm -it llm-devcontainer:latest"
            '');
          };

          # Test runner
          test = {
            type = "app";
            program = toString (import ./apps/test.nix { inherit pkgs self; });
          };

          # Quick shell in a test container (for development)
          shell = {
            type = "app";
            program = toString (pkgs.writeShellScript "llm-devcontainer-shell" ''
              set -euo pipefail

              # Check if image exists
              if ! podman image exists llm-devcontainer:latest; then
                echo "[llm-devcontainer] Image not found, building..."
                nix run ${self}#build
              fi

              # Workspace name from current directory
              WORKSPACE="/$(basename "$(pwd)")"

              exec podman run \
                --rm \
                -it \
                --userns=keep-id \
                --network=pasta \
                --read-only \
                --cap-drop=ALL \
                --security-opt=no-new-privileges \
                -w "$WORKSPACE" \
                --tmpfs=/tmp:rw,exec,nosuid,nodev,size=2g \
                --tmpfs=/var:rw,noexec,nosuid,nodev,size=512m \
                --tmpfs=/run:rw,noexec,nosuid,nodev,size=64m \
                -v /nix/store:/nix/store:ro \
                -v "$(pwd):$WORKSPACE:rw" \
                -v llm-devcontainer-home-default:/home/developer:rw,U \
                llm-devcontainer:latest \
                "$@"
            '');
          };

          # Run claude directly
          claude = {
            type = "app";
            program = toString (pkgs.writeShellScript "llm-devcontainer-claude" ''
              set -euo pipefail

              # Check if image exists
              if ! podman image exists llm-devcontainer:latest; then
                echo "[llm-devcontainer] Image not found, building..."
                nix run ${self}#build
              fi

              # Create volumes if needed
              podman volume create claude-auth-default 2>/dev/null || true
              podman volume create llm-devcontainer-home-default 2>/dev/null || true

              # Workspace name from current directory
              WORKSPACE="/$(basename "$(pwd)")"

              # Build CLAUDE.md mount if it exists
              CLAUDE_MD_MOUNT=""
              if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
                CLAUDE_MD_MOUNT="-v $HOME/.claude/CLAUDE.md:/home/developer/.claude/CLAUDE.md:ro"
              fi

              exec podman run \
                --rm \
                -it \
                --userns=keep-id \
                --network=pasta \
                --read-only \
                --cap-drop=ALL \
                --security-opt=no-new-privileges \
                -w "$WORKSPACE" \
                --tmpfs=/tmp:rw,exec,nosuid,nodev,size=2g \
                --tmpfs=/var:rw,noexec,nosuid,nodev,size=512m \
                --tmpfs=/run:rw,noexec,nosuid,nodev,size=64m \
                -v /nix/store:/nix/store:ro \
                -v "$(pwd):$WORKSPACE:rw" \
                -v llm-devcontainer-home-default:/home/developer:rw,U \
                -v claude-auth-default:/home/developer/.claude:rw,U \
                $CLAUDE_MD_MOUNT \
                llm-devcontainer:latest \
                claude "$@"
            '');
          };
        };

        # Checks
        checks = {
          # Verify flake builds correctly
          build = baseImage;

          # Shellcheck the shell scripts
          shellcheck = pkgs.runCommand "shellcheck" {
            buildInputs = [ pkgs.shellcheck ];
          } ''
            shellcheck ${self}/container/entrypoint.sh
            touch $out
          '';
        };
      }
    );
}
