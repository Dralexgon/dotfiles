{ config, pkgs, lib, inputs, ... }:

{
  # This module is used to configure the boot animation.

  # It's the beautiful animation that appears when you start your computer
  # and displays the manufacturer's logo with the distribution's logo.

  boot.plymouth = {
    enable = true;
    themePackages = [ pkgs.catppuccin-plymouth ];
  };
}
