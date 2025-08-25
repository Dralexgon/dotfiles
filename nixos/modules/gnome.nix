{ pkgs, ... }:

{
  services.xserver = {
    displayManager.gdm.enable = true;
    #displayManager.gdm.enableGnomeKeyring = true;
    desktopManager.gnome.enable = true;
  };

  # Enable the X11 windowing system, needed for Gnome (XWayland).
  services.xserver = {
    enable = true;
    # xkb = {
    #   layout = "us";
    #   variant = "";
    # };
  };

  environment.systemPackages = with pkgs; [
    # Terminal <3 meow
    kitty # In kitty.conf set linux_display_server to x11 to have the same look as gnome-terminal
    # Set font to JetBrains Mono Nerd Font Mono if you want to use nerd fonts

    # Useful gnome tools
    gnome-tweaks
    gnome-extension-manager
    gnomeExtensions.appindicator
    gnomeExtensions.emoji-copy
    gnomeExtensions.gsconnect # Android phone integration
    gnomeExtensions.speedinator # Control the speed of gnome-shell animations

    # Choose your favorite internet speed meter
    gnomeExtensions.network-stats
    #gnomeExtensions.speed-buzz-internet-speed-meter
    #gnomeExtensions.internet-speed-meter
    #gnomeExtensions.crazy-internet-speed-meter

    # Nice and leightweight
    gnomeExtensions.user-themes
    gnomeExtensions.blur-my-shell
    #gnomeExtensions.custom-accent-colors

    # Very nice but heavy
    gnomeExtensions.dash2dock-lite # Dash2DockAnimated
    gnomeExtensions.compiz-windows-effect
    gnomeExtensions.compiz-alike-magic-lamp-effect
    gnomeExtensions.burn-my-windows
    gnomeExtensions.desktop-cube

    gnome-terminal # Better gnome terminal but
    # just use kitty instead and put
    # `linux_display_server = x11` in kitty.conf

    # Better gnome terminal and can use themes but
    # must be installed with flatpak for full features.
    # Unfortunately, NixOS and other package managers... You know
    blackbox-terminal

    # Gnome music contribution
    # gnome-builder
    # meson
    # pkg-config
    # libadwaita
    # gtk4
    # flatpak-builder
    # apostrophe # Markdown editor
    # element-desktop # Matrix client
    # fractal # Better matrix client ?

    #nix-software-center
  ];

  # services.flatpak.enable = true;
  # flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}
