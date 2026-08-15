{ inputs, config, pkgs, ... }:

let
  common = import ./home-common.nix { inherit inputs config pkgs; };
in
{
  imports = [ common ];


  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home = common.home // {
    packages = common.home.packages;
    username = "bbarker";
    homeDirectory = "/Users/bbarker";
    stateVersion = "24.05";
  };
}
