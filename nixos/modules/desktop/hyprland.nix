{ config, lib, pkgs, ... }:

# Hyprland, also turned on by caelestia (desktop.enabled, see default.nix).
# Its login screen (SDDM + the predatoria theme) is in default.nix.
lib.mkIf (lib.elem "hyprland" config.desktop.enabled || lib.elem "caelestia" config.desktop.enabled) {
  programs.hyprland = {
    enable = true;
    # package = pkgs-stable.hyprland; # to go to an old version of hyprland
    withUWSM = true; # to enable gtk portals
  };
  i18n.inputMethod.enable = false; # disable a notif

  # Screen sharing and gtk apps support
  xdg.portal.enable = true;
  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
  ];
}
