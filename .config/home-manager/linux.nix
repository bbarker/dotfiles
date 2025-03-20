{ inputs, config, pkgs, ... }:

{
  packages = with pkgs; [
    appimage-run
  ];

}
