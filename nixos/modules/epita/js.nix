{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nodejs_20
    yarn
    typescript
  ];
}