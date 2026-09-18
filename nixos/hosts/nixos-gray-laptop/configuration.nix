# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, config, ... }:

{
  networking.hostName = "nixos-gray-laptop";

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix


    # You probably shouldn't remove it
    ./../../core.nix


    # Main modules
    ./../../modules/gnome.nix
    ./../../modules/caelestia.nix
    ./../../modules/hyprland.nix
    # ./../../modules/wayfire.nix
    # ./../../modules/auto-update.nix

    # Hardware specific modules
    #./../../modules/nvidia-drivers.nix
    #./../../modules/razer.nix
    ./../../modules/swap.nix

    # Personal modules
    # ./../../modules/file-transfer.nix
    # ./../../modules/neovim.nix
    ./../../modules/epita/core.nix
    ./../../modules/gaming.nix
    ./../../modules/minecraft.nix 
    # ./../../modules/boot-animation.nix
    ./../../modules/ricing.nix
    ./../../modules/ricing-tools.nix
    # ./../../modules/flatpak.nix
    ./../../modules/classidoc.nix
  ];
 
  # Configure console keymap
  console.keyMap = "fr";

  services.xserver = {
    xkb = {
      layout = "fr";
      variant = "";
    };
  };

  # boot.extraModulePackages = [ config.boot.kernelPackages.rtl88x2bu ]; # specific driver for my wifi card
}
