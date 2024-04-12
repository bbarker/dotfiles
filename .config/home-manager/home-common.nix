#
# TODO: add ssh config
#     : look into adding chezmoi or stow for syncing config files and others into home dir
#     : (both are in nixpkgs)
#

{ config, pkgs, ... }:

{
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # nixpkgs.overlays = [
  #   (import (builtins.fetchTarball {
  #     url = https://github.com/nix-community/neovim-nightly-overlay/archive/master.tar.gz;
  #   }))
  # ];

  home.packages = with pkgs; [
    alacritty
    tmux
    helix
    nushell

    git
    gitAndTools.gh
    tig
    nodejs

    fzf
    httpie
    jq
    ripgrep
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


    python3 # needed for sshuttle

    # must be last
    zsh-syntax-highlighting
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

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "24.05";
}
