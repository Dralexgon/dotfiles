{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    sbctl
  ];
}