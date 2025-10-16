{ inputs, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    inputs.quickshell.packages.${pkgs.system}.default
    kdePackages.qtdeclarative
  ];
}