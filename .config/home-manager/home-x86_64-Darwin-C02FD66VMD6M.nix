{ inputs, config, pkgs, ... }:

let
  common = import ./home-common.nix { inherit inputs config pkgs; };
in
{
  imports = [ common ];


  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "bbarker";
  home.homeDirectory = "/Users/bbarker";
  home.sessionVariables = common.home.sessionVariables;
  programs = common.programs;
}
