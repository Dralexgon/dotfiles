{ pkgs23, ... }:

{
  environment.systemPackages = [
    pkgs23.texliveFull
    pkgs23.fontconfig
  ];
}

