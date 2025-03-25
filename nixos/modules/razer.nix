{ config, pkgs, lib, inputs, ... }:

{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # GUI to manage rgb
    polychromatic
  ];
  
  hardware.openrazer = {
    enable = true;
    users = ["alex"];
  };
}
