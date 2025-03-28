{ config, pkgs, lib, inputs, ... }:

{
  services.flatpak.enable = true;

  environment.systemPackages = with pkgs; [
    gnome-software
  ];

  # flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}
