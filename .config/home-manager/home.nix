{ config, pkgs, ... }:

{
  imports = [ ./home-common.nix ];


  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "bbarker";
  
}