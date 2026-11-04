{ config, pkgs, lib, inputs, ... }:

{
  networking.hostName = "nixos";

  imports = [
    # Include the results of the hardware scan.
    /etc/nixos/hardware-configuration.nix


    # You probably shouldn't remove it
    ./../../core.nix

    # Enabled modules and extra packages (edit with `nix run ~/dotfiles#nixcfg`)
    (import ./../../state.nix ./state.json)
  ];
}