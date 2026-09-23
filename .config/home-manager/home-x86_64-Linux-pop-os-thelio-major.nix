{ inputs, config, pkgs, ... }@args:

let
  common = import ./home-common.nix { inherit inputs config pkgs; };
  linuxCommon = import ./linux.nix args;
  x11home = import ./x11.nix { inherit inputs config pkgs; };
  pkgsUnstable = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/6774f7bc253789b113a4f39285dc0fa100abeacc.tar.gz"; # 09/22/26
    sha256 = "sha256:1jmanihn33h564jk6fzpcjrrhyhchb11mqqkh6bdplnb5kw8i21i";
  }) {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  imports = [ common ];

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home = common.home // {
    packages = linuxCommon.packages ++ x11home.packages ++ common.home.packages ++ [
      pkgs.tlaplusToolbox
      # Local LLMs (see ~/workspace/local_ai). llama-server with CUDA, wrapped
      # with nixGL for GPU access (requires: home-manager switch --impure);
      # llama-swap routes requests to a llama-server per model.
      (linuxCommon.wrapWithNixGL (pkgsUnstable.llama-cpp.override { cudaSupport = true; }))
      pkgsUnstable.llama-swap
    ];
    username = "bbarker";
    homeDirectory = "/home/bbarker";
    sessionVariables = common.home.sessionVariables // {
      # Not sure how much this helps yet - trying to get XDG working well
      XDG_CURRENT_DESKTOP = "pop:GNOME";
      XDG_MENU_PREFIX = "gnome-";
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus";
    };
    stateVersion = "24.05";
  };
}
