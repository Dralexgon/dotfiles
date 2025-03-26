{ config, pkgs, lib, inputs, ... }:

{
  boot.loader.grub.theme = pkgs.catppuccin-grub;

  environment.systemPackages = with pkgs; [
    catppuccin-cursors.macchiatoMauve
  ];
}
