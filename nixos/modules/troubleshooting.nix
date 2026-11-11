{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    smartmontools
    memtest86plus
  ];
}
