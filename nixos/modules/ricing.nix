{ config, pkgs, lib, inputs, ... }:

{
  environment.systemPackages = with pkgs; [

    # Ricing visual in the terminal
    fastfetch
    neofetch
    cmatrix
    cbonsai
    pipes-rs
    cava

    # catppuccin rice
    catppuccin-cursors.macchiatoMauve
    # catppuccin-gtk
  ];
}
