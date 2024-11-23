{ inputs, config, pkgs, ... }:

let
  common = import ./home-common.nix { inherit inputs config pkgs; };
  x11home = import ./x11.nix { inherit inputs config pkgs; };
in
{
  imports = [ common ];

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home = common.home // {
    packages = x11home.packages ++ common.home.packages;
    username = "bbarker";
    homeDirectory = "/home/bbarker";
  };
  programs = common.programs;
 }
