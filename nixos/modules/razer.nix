{ config, pkgs, lib, inputs, ... }:

{
  environment.systemPackages = with pkgs; [
    # GUI to manage rgb
    polychromatic
  ];
  
  hardware.openrazer = {
    enable = true;
    users = ["alex"];
  };
}
