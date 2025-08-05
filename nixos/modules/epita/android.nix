{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    android-studio
    # android-studio-full
  ];
}