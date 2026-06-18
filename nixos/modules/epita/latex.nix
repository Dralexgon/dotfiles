{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    texliveFull
    fontconfig
  ];
}

