{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  environment.systemPackages = with pkgs; [

    # Ricing visual in the terminal
    fastfetch
    # neofetch #unmainted, use fastfetch instead
    cmatrix
    cbonsai
    pipes-rs
    cava
    eza # better ls

    # catppuccin rice
    # catppuccin-cursors.macchiatoMauve
    # catppuccin-gtk
  ];
}
