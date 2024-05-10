{ inputs, config, pkgs, ... }:

let
  common = import ./home-common.nix { inherit inputs config pkgs; };
  waylandHome = import ./wayland.nix { inherit inputs config pkgs; };
  nixosHome = import ./nixos.nix { inherit inputs config pkgs; };
in
{
  imports = [ common ];
  home.packages = waylandHome.packages ++ common.home.packages ++ nixosHome.packages;

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "bbarker";
  home.homeDirectory = "/home/bbarker";
  home.sessionVariables = common.home.sessionVariables;
  programs = common.programs;
}
