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

          # Optional: Enable USB passthrough for hardware development
          # enableUSB = true;
          # usbDevices = [
          #   "0483:374b"  # ST-Link
          #   "1a86:7523"  # CH340
          # ];

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
          # Usage: nix run .#dev
          dev = {
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

          # Hardware development variant (if USB enabled)
          # Usage: nix run .#dev-hw
          dev-hw = {
            type = "app";
            program = toString container.devHw;
          };
        };

        # Default app is the dev shell
        apps.default = self.apps.${system}.dev;
      }
    );
}
