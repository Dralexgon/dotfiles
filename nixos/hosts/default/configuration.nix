{ config, pkgs, lib, inputs, ... }:

{
  networking.hostName = "nixos";

  imports = [
    # Include the results of the hardware scan.
    /etc/nixos/hardware-configuration.nix


    # You probably shouldn't remove it
    ./../../core.nix


    # Main modules
    ./../../modules/gnome.nix
    ./../../modules/hyprland.nix
    ./../../modules/auto-update.nix

    # Hardware specific modules
    #./../../modules/nvidia-drivers.nix
    #./../../modules/razer.nix # Derivation doesn't build temporarily
    #./../../modules/swap.nix

    # Personal modules
    ./../../modules/neovim.nix
    ./../../modules/epita.nix
    ./../../modules/gaming.nix
    ./../../modules/boot-animation.nix
    ./../../modules/ricing.nix
    ./../../modules/ricing-tools.nix
    ./../../modules/flatpak.nix
  ];
}