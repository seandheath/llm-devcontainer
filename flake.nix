{
  description = "nix-sandbox: Container-based Claude Code development environment";

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

        # Egress proxy configuration (stub)
        egressProxy = import ./lib/egress-proxy.nix;
      };

    in
    {
      # Export library functions
      inherit lib;

      # Templates for new projects
      templates = {
        default = {
          path = ./templates/default;
          description = "Basic nix-sandbox project with Claude Code";
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
          name = "nix-sandbox-base";
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

        # Development shell for working on nix-sandbox itself
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
            echo "nix-sandbox development shell"
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
            program = toString (pkgs.writeShellScript "nix-sandbox-build" ''
              set -euo pipefail

              echo "[nix-sandbox] Stage 1: Building Nix base image..."
              nix build ${self}#base-image --out-link result-base-image

              echo "[nix-sandbox] Loading base image into podman..."
              podman load < result-base-image

              echo "[nix-sandbox] Stage 2: Building final image with Claude Code..."
              podman build \
                -t nix-sandbox:latest \
                -f ${self}/container/Containerfile \
                ${self}

              echo "[nix-sandbox] Build complete!"
              echo ""
              echo "Image: nix-sandbox:latest"
              echo "Run:   podman run --rm -it nix-sandbox:latest"
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
            program = toString (pkgs.writeShellScript "nix-sandbox-shell" ''
              set -euo pipefail

              # Check if image exists
              if ! podman image exists nix-sandbox:latest; then
                echo "[nix-sandbox] Image not found, building..."
                nix run ${self}#build
              fi

              exec podman run \
                --rm \
                -it \
                --userns=keep-id \
                --network=pasta \
                --read-only \
                --cap-drop=ALL \
                --security-opt=no-new-privileges \
                --tmpfs=/tmp:rw,exec,nosuid,nodev,size=2g \
                --tmpfs=/var:rw,noexec,nosuid,nodev,size=512m \
                --tmpfs=/run:rw,noexec,nosuid,nodev,size=64m \
                --tmpfs=/home/developer/.cache:rw,exec,nosuid,nodev,size=2g \
                --tmpfs=/home/developer/.local:rw,exec,nosuid,nodev,size=1g \
                --tmpfs=/home/developer/.npm:rw,exec,nosuid,nodev,size=512m \
                --tmpfs=/home/developer/.claude:rw,noexec,nosuid,nodev,size=64m \
                -v /nix/store:/nix/store:ro \
                -v "$(pwd):/workspace:rw" \
                nix-sandbox:latest \
                "$@"
            '');
          };

          # Run claude directly
          claude = {
            type = "app";
            program = toString (pkgs.writeShellScript "nix-sandbox-claude" ''
              set -euo pipefail

              # Check if image exists
              if ! podman image exists nix-sandbox:latest; then
                echo "[nix-sandbox] Image not found, building..."
                nix run ${self}#build
              fi

              # Create auth volume if needed
              podman volume create claude-auth-default 2>/dev/null || true

              exec podman run \
                --rm \
                -it \
                --userns=keep-id \
                --network=pasta \
                --read-only \
                --cap-drop=ALL \
                --security-opt=no-new-privileges \
                --tmpfs=/tmp:rw,exec,nosuid,nodev,size=2g \
                --tmpfs=/var:rw,noexec,nosuid,nodev,size=512m \
                --tmpfs=/run:rw,noexec,nosuid,nodev,size=64m \
                --tmpfs=/home/developer/.cache:rw,exec,nosuid,nodev,size=2g \
                --tmpfs=/home/developer/.local:rw,exec,nosuid,nodev,size=1g \
                --tmpfs=/home/developer/.npm:rw,exec,nosuid,nodev,size=512m \
                --tmpfs=/home/developer/.claude:rw,noexec,nosuid,nodev,size=64m \
                -v /nix/store:/nix/store:ro \
                -v "$(pwd):/workspace:rw" \
                -v claude-auth-default:/auth:rw \
                nix-sandbox:latest \
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
