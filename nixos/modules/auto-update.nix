{ config, pkgs, lib, inputs, ... }:

{
  system.autoUpgrade.enable = true; # Disabled by default
  boot.kernelPackages = pkgs.linuxPackages_latest;
}
