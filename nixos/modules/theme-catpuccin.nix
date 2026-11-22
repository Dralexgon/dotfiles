{ config, pkgs, lib, inputs, ... }:

{
  boot.loader.grub.theme = pkgs.catppuccin-grub;
  # Mouse pointer: Bibata everywhere (cursors.nix)
}
