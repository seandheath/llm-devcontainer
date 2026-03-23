{
  description = "Project using llm-devcontainer for Claude Code development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # llm-devcontainer provides container infrastructure
    llm-devcontainer.url = "github:seandheath/llm-devcontainer";
  };

  outputs = { self, nixpkgs, flake-utils, llm-devcontainer }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Get mkDevContainer from llm-devcontainer
        containerLib = llm-devcontainer.lib.mkDevContainer { inherit pkgs; };

        # Project name - update this for your project
        projectName = "my-project";  # TODO: Update project name

        # Generate container runners for this project
        container = containerLib.mkDevContainer {
          name = projectName;
          projectPath = toString ./.;

          # Optional: Additional volume mounts
          # extraMounts = [
          #   { host = "/path/on/host"; container = "/path/in/container"; opts = "ro"; }
          # ];

          # Optional: Additional environment variables
          # extraEnv = {
          #   MY_VAR = "value";
          # };
        };

        # Wrapper script to run containerized claude
        claudeWrapper = pkgs.writeShellScriptBin "claude" ''
          exec ${container.claude} "$@"
        '';

      in {
        # Packages (for pre-building)
        packages = {
          shell = container.shell;
          claude = container.claude;
        };

        # Development shell with containerized claude
        devShells.default = pkgs.mkShell {
          buildInputs = [
            claudeWrapper
            # Add your project's native dependencies here
          ];
          shellHook = ''
            export LLM_DEVCONTAINER=1
            export LLM_PROJECT_NAME="${projectName}"
            if [[ -n "$ZSH_VERSION" ]]; then
              export PROMPT="%F{cyan}[${projectName}]%f $PROMPT"
            elif [[ -n "$BASH_VERSION" ]]; then
              export PS1="\[\033[36m\][${projectName}]\[\033[0m\] $PS1"
            fi
          '';
        };

        # Apps for container-based development
        apps = {
          # Interactive shell in container
          # Usage: nix run .#shell
          shell = {
            type = "app";
            program = toString container.shell;
          };

          # Run Claude directly in container
          # Usage: nix run .#claude
          claude = {
            type = "app";
            program = toString container.claude;
          };

          # Start container in background
          # Usage: nix run .#detached
          detached = {
            type = "app";
            program = toString container.detached;
          };

          # Update llm-devcontainer and rebuild image
          # Usage: nix run .#update
          update = {
            type = "app";
            program = toString (pkgs.writeShellScript "llm-devcontainer-update" ''
              set -euo pipefail
              echo "[llm-devcontainer] Updating flake inputs..."
              nix flake update llm-devcontainer

              echo "[llm-devcontainer] Rebuilding container image..."
              nix run github:seandheath/llm-devcontainer#build

              echo "[llm-devcontainer] Update complete"
            '');
          };
        };

        # Default app is the shell
        apps.default = self.apps.${system}.shell;
      }
    );
}
