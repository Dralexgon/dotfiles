{ config, pkgs, lib, inputs, ... }:

{
  services.xserver = {
    displayManager.gdm.enable = true;
    #displayManager.gdm.enableGnomeKeyring = true;
    desktopManager.gnome.enable = true;
  };

  # Enable the X11 windowing system, needed for Gnome (XWayland).
  services.xserver = {
    enable = true;
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  environment.systemPackages = with pkgs; [

    # Useful gnome tools
    gnome-tweaks
    gnome-extension-manager
    gnomeExtensions.emoji-copy
    gnomeExtensions.gsconnect

    # Choose your favorite
    gnomeExtensions.network-stats
    gnomeExtensions.speed-buzz-internet-speed-meter
    gnomeExtensions.internet-speed-meter
    gnomeExtensions.crazy-internet-speed-meter
    gnomeExtensions.speedinator

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

    # Flatpak maybe
    #flatpak
    #gnome-software

    # Gnome music contribution
    # gnome-builder
    # meson
    # pkg-config
    # libadwaita
    # gtk4
    # flatpak-builder
    # apostrophe # Markdown editor
    # element-desktop

    #nix-software-center
  ];

  # services.flatpak.enable = true;
  # flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}
