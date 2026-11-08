#
# TODO: add ssh config
#     : look into adding chezmoi or stow for syncing config files and others into home dir
#     : (both are in nixpkgs)
#

{ inputs, config, pkgs, ... }:

let
  pkgsUnstable = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/6dadaf4375be35033e1c84395adbd53ff5fded96.tar.gz"; # 2026-11-04, nixpkgs-unstable
    sha256 = "sha256:1g9sadx7zszll972hlv78675vc5vz2iw8v9jzs4338ccx8gzp48g";
  }) {
    system = "SYSTEM_PLACEHOLDER";
    config.allowUnfree = true;    
  };
in

{
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # nixpkgs.overlays = [
  #   (import (builtins.fetchTarball {
  #     url = https://github.com/nix-community/neovim-nightly-overlay/archive/master.tar.gz;
  #   }))
  # ];

  home.packages = with pkgs; [
    
    # alacritty # nixGL issue on non-NixOS
    tmux
    helix
    bashInteractive
    pkgsUnstable.nushell # newer than the stable channel's, to match project devShells

    # image viewers
    oculante
    viu
    # ai-sh
    # to use alternative claude-code versions
    # first do `npm set prefix ~/.npm-global`
    nodejs
    bun

    git
    gh
    meld
    openssh
    tig
    deno
    rclone

    dogedns
    fzf
    httpie
    jq
    ripgrep-all
    htop
    shellcheck
    sccache

    awscli2
    pgcli

    coursier
    metals
    scalafmt
    sbt
    scala
    scala-cli

    visualvm

    unison-ucm
    tlaplus # tlc, for the TLA+ models stored in Unison libraries

    python3 # needed for sshuttle

    # work
    kubectl

    # For tiling WMs
    haskellPackages.yeganesh

    # must be last
    zsh-syntax-highlighting
  ] ++ lib.optionals (stdenv.hostPlatform.system != "aarch64-linux") [
    # These derivations are unsuitable for small Linux ARM64 systems: Bloop
    # has no ARM64 build, and Claude Code's fixup phase exceeds the Pi's RAM.
    bloop
    claude-code
  ];

  home.file.".local/bin" = {
    source = ./scripts;
    recursive = true;
    executable = true;
  };
  home.sessionPath = [
    "$HOME/.local/bin"
  ];
  
  home.sessionVariables = {
    EDITOR = "hx";
  };

  #programs.zsh.enableAutosuggestions = true;

  programs.git = {
    enable = true;

    # includes = [
    #   { path = "~/.gitconfig-public"; condition = "gitdir:~/workspace/"; }
    #   { path = "~/.gitconfig-WH"; condition = "gitdir:~/WH/"; }
    # ];

    settings = {
      color = {
        ui = "auto";
      };
      diff = {
        tool = "meld";
      };
      difftool = {
        prompt = false;
      };
      merge = {
        tool = "meld";
      };
      mergetool = {
        prompt = false;
      };
      pull = {
        rebase = true;
      };
    };
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  programs.bash.enable = true;
  programs.bash.profileExtra = ''
    source "$HOME/.cargo/env"
    if [ -d "/var/cache/sccache" ]; then
      export SCCACHE_DIR="/var/cache/sccache"
      export RUSTC_WRAPPER="sccache"
    fi
  '';
  programs.bash.initExtra = ''
    # Source session vars for non-login shells (e.g., terminal emulators)
    [[ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]] && \
      source "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"

    # Use shared sccache directory if present
    if [ -d "/var/cache/sccache" ]; then
      export SCCACHE_DIR="/var/cache/sccache"
      export RUSTC_WRAPPER="sccache"
    fi
  '';
  programs.zsh.enable = true;
  programs.zsh.initContent = ''
    if [ -d "/var/cache/sccache" ]; then
      export SCCACHE_DIR="/var/cache/sccache"
      export RUSTC_WRAPPER="sccache"
    fi
  '';

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  #
  # This should be set in individual machine configs
  # home.stateVersion = "24.05";
}
