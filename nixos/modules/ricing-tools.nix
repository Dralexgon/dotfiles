{ config, pkgs, lib, inputs, ... }:

{
  environment.systemPackages = with pkgs; [
    fastfetch # Most important ricing tool (that's the nice logo in the terminal)
    btop # System monitor

    # Theming (GTK, icons, etc)
    dconf-editor
    nwg-look
    home-manager

    # Generate color schemes from images
    python3
    pywal

    eww # This can be used to create a custom bar. I will try to do my own menu with it

    # To draw art
    # python312Full
    # python3Packages.tkinter
  ];
}
