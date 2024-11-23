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
    packages = x11home.packages ++ common.home.packages ++ [
      pkgs.tlaplusToolbox
    ];
    username = "bbarker";
    homeDirectory = "/home/bbarker";
    sessionVariables = common.home.sessionVariables // {
      # Not sure how much this helps yet - trying to get XDG working well
      XDG_CURRENT_DESKTOP = "pop:GNOME";
      XDG_MENU_PREFIX = "gnome-";
    };
  };
  programs = common.programs;
}
