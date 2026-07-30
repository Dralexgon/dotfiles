{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    kvmtool
    gnome-boxes
  ];
}