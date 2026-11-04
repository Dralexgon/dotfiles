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

    # Enabled modules and extra packages (edit with `nix run ~/dotfiles#nixcfg`)
    (import ./../../state.nix ./state.json)
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
