{ pkgs, ... } :

{
  environment.systemPackages = with pkgs; [
    celeste # Sync your files to any cloud
    cartero # Test http requests
    clapgrep # UI for grep (find text in files)
    cavalier # Cava audio visualizer UI
    calligraphy # Turn text into ascii art
    elastic # Design animations
    gaphor # UML diagram editor
    # setzer # Latex editor
    # apostrophe # Markdown editor
    # book-up # Better markdown editor ?
    folio # Better markdown editor ?
    ghex # Hex editor
    # impression # Write iso on usb # Not needed : right click on iso file and select gnome writer
    turtle # UI for git

    # Not in NixOS :
    # https://gitlab.gnome.org/World/design/icon-library
  ];
}