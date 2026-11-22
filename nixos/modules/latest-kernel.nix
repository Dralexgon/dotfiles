{ pkgs, ... }:

{
  # Newest kernel instead of the LTS one (NixOS default)
  boot.kernelPackages = pkgs.linuxPackages_latest;
}
