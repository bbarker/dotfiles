{ config, pkgs, ... }:

{
  imports = [ ./home-common.nix ];


  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "bbarker";
  home.homeDirectory = "/Users/bbarker";
  home.sessionVariables = common.home.sessionVariables;
  programs = common.programs;
}
