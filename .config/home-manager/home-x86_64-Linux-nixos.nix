{ inputs, config, pkgs, ... }:

let
  common = import ./home-common.nix { inherit inputs config pkgs; };
  waylandHome = import ./wayland.nix { inherit inputs config pkgs; };
  nixosHome = import ./nixos.nix { inherit inputs config pkgs; };
in
{
  imports = [ common ];

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home = common.home // {
    packages = waylandHome.packages ++ common.home.packages ++ nixosHome.packages;
    username = "bbarker";
    homeDirectory = "/home/bbarker";
  };
  programs = common.programs;
}
