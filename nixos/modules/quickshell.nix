{ inputs, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
    kdePackages.qtdeclarative
  ];
}