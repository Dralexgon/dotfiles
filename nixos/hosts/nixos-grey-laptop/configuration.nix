# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, inputs, ... }:

{
  networking.hostName = "nixos-grey-laptop";

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix


    # You probably shouldn't remove it
    ./../../core.nix


    # Main modules
    ./../../modules/gnome.nix
    #./../../modules/hyprland.nix
    #./../../modules/auto-update.nix

    # Hardware specific modules
    #./../../modules/nvidia-drivers.nix
    #./../../modules/razer.nix
    ./../../modules/swap.nix

    # Personal modules
    ./../../modules/neovim.nix
    ./../../modules/epita.nix
    #./../../modules/gaming.nix
    ./../../modules/boot-animation.nix
    ./../../modules/ricing.nix
    #./../../modules/ricing-tools.nix
    #./../../modules/flatpak.nix
  ];

  # Configure console keymap
  console.keyMap = "us";

}
