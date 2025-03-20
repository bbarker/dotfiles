#
# TODO: add ssh config
#     : look into adding chezmoi or stow for syncing config files and others into home dir
#     : (both are in nixpkgs)
#

{ inputs, config, pkgs, ... }:

let
  pkgsUntable = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/905537956250bd4c0d7de778b8a8ee9af6daac58.tar.gz"; # 03/06/25
    sha256 = "sha256:0indqp22d7w8zl2wfnzq0id1l697xc7rsxpf2z58hr28inra1r9v";
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
    nushell
    # ai-sh
    pkgsUntable.claude-code

    git
    gitAndTools.gh
    openssh
    tig
    nodejs
    deno

    dogedns
    fzf
    httpie
    jq
    ripgrep-all
    htop
    shellcheck

    awscli2
    pgcli

    coursier
    bloop
    scalafmt
    sbt
    scala
    scala-cli

    visualvm

    unison-ucm

    python3 # needed for sshuttle

    # work
    kubectl

    # For tiling WMs
    haskellPackages.yeganesh

    # must be last
    zsh-syntax-highlighting
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

    extraConfig = {
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
  '';
  programs.zsh.enable = true;

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
