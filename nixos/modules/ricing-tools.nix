{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    fastfetch # Most important ricing tool (that's the nice logo in the terminal)
    btop # System monitor

    # Theming (GTK, icons, etc)
    gdm-settings # Settings for the GDM login screen
    # iconic # Custom icons on folders (need to update flake.lock)
    schemes # Create custom code color schemes
    
    # For managing themes and other settings
    home-manager 
    lxappearance
    nwg-look
    dconf-editor
    gradience

    # Generate color schemes from images
    python3
    pywal

    eww # This can be used to create a custom bar. I will try to do my own menu with it

    # To draw art
    # python312Full
    # python3Packages.tkinter
  ];
}
