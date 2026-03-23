# Base OCI image for Claude Code development containers
#
# Built with dockerTools.buildLayeredImage for efficient layer caching.
# This image provides the Nix foundation - Claude Code itself is installed
# in stage 2 via Containerfile to avoid nix sandbox network restrictions.
#
# References:
# - https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-dockerTools
# - https://ryantm.github.io/nixpkgs/builders/images/dockertools/

{ pkgs
, lib ? pkgs.lib
, name ? "nix-sandbox-base"
, tag ? "latest"
}:

let
  # User/group configuration matching entrypoint.sh expectations
  user = "developer";
  uid = "1000";
  gid = "1000";
  home = "/home/${user}";

  # Generate config files as derivations to avoid shell escaping issues
  passwdFile = pkgs.writeText "passwd" ''
    root:x:0:0:root:/root:/bin/zsh
    ${user}:x:${uid}:${gid}:Developer:${home}:/bin/zsh
    nobody:x:65534:65534:Nobody:/nonexistent:/sbin/nologin
  '';

  groupFile = pkgs.writeText "group" ''
    root:x:0:
    ${user}:x:${gid}:
    nobody:x:65534:
    dialout:x:20:${user}
    plugdev:x:46:${user}
  '';

  shadowFile = pkgs.writeText "shadow" ''
    root:!:1::::::
    ${user}:!:1::::::
    nobody:!:1::::::
  '';

  nixConfFile = pkgs.writeText "nix.conf" ''
    experimental-features = nix-command flakes
    trusted-users = root ${user}
    sandbox = false
    store = /nix/store
    log-lines = 25
  '';

  profileFile = pkgs.writeText "nix.sh" ''
    # Nix profile setup
    export NIX_PROFILES="/nix/var/nix/profiles/default $HOME/.nix-profile"
    export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
    export PATH="$HOME/.npm-global/bin:$PATH"
  '';

  zshenvFile = pkgs.writeText "zshenv" ''
    ZDOTDIR=${home}
  '';

  # Essential packages for development environment
  basePackages = with pkgs; [
    # Core utilities
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    gnutar
    gzip
    xz
    bzip2
    which
    less

    # Shell and environment
    zsh
    bashInteractive
    direnv
    nix-direnv

    # Version control
    git
    git-lfs

    # Build tools
    gnumake
    pkg-config

    # Node.js for Claude Code
    nodejs_22

    # Nix tooling
    nix
    nixfmt
    nil  # Nix LSP

    # Text editing (minimal)
    neovim

    # Networking utilities
    curl
    cacert

    # Process management
    procps
    psmisc
  ];

in pkgs.dockerTools.buildLayeredImage {
  inherit name tag;

  # Layer configuration for efficient caching
  # Packages that change rarely go in lower layers
  contents = basePackages;

  # Maximum layers for better cache efficiency
  maxLayers = 125;

  # Additional configuration
  extraCommands = ''
    # Create directory structure
    mkdir -p tmp var/tmp run
    chmod 1777 tmp var/tmp

    # User directories
    mkdir -p home/${user}/.config home/${user}/.cache
    mkdir -p home/${user}/.local/share home/${user}/.local/state
    mkdir -p home/${user}/.npm home/${user}/.claude

    # Workspace mount point
    mkdir -p workspace

    # System directories - remove existing symlinks if present
    rm -rf etc/nix etc/ssl etc/zsh etc/profile.d
    mkdir -p etc/nix etc/ssl/certs etc/zsh etc/profile.d

    # Copy CA certificates for HTTPS
    cp -L ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt

    # Copy config files from derivations
    cp ${passwdFile} etc/passwd
    cp ${groupFile} etc/group
    cp ${shadowFile} etc/shadow
    chmod 644 etc/passwd etc/group
    chmod 640 etc/shadow

    # Nix configuration
    cp ${nixConfFile} etc/nix/nix.conf

    # Shell configuration
    cp ${zshenvFile} etc/zsh/zshenv
    cp ${profileFile} etc/profile.d/nix.sh
  '';

  config = {
    # Default user (overridden by --userns=keep-id)
    User = user;
    WorkingDir = "/workspace";

    Env = [
      "HOME=${home}"
      "USER=${user}"
      "PATH=${home}/.npm-global/bin:${home}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"
      "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
      "LANG=C.UTF-8"
      "LC_ALL=C.UTF-8"
      "TERM=xterm-256color"
      "SHELL=/bin/zsh"
      "EDITOR=nvim"
      "NIX_CONF_DIR=/etc/nix"
    ];

    # Labels for identification
    Labels = {
      "org.opencontainers.image.title" = "nix-sandbox-base";
      "org.opencontainers.image.description" = "Base image for Claude Code development containers";
      "org.opencontainers.image.source" = "https://github.com/user/nix-sandbox";
    };

    # Entrypoint will be set in stage 2
    Cmd = [ "/bin/zsh" ];
  };
}
