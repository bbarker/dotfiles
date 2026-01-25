{ inputs, config, pkgs, ... }:

let
  common = import ./home-common.nix { inherit inputs config pkgs; };
  linuxCommon = import ./linux.nix { inherit inputs config pkgs; };
  x11home = import ./x11.nix { inherit inputs config pkgs; };
  pkgsUnstable = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/523257564973361cc3e55e3df3e77e68c20b0b80.tar.gz"; # 01/24/26
    sha256 = "sha256:04pg38yzy28kkrxgn4hjgdzpr3zlxzqi2g7k2gi8fkwgkb3a58xi";
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
      pkgsUnstable.ollama-cuda
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
