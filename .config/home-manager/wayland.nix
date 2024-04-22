{ inputs, config, pkgs, ... }:

{
  packages = with pkgs; [
    wl-clipboard
  ];

}
