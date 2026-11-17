{ lib, pkgs, ... }:

# Mouse pointer: Bibata Modern Classic, size 24, everywhere.
# - XCURSOR_* for X11/XWayland apps and Hyprland (which falls back to XCursor themes)
# - GTK / GNOME through dconf (org.gnome.desktop.interface)
# - the SDDM login screen (themes/sddm/rice)
# Caelestia's Hyprland reads its own cursorTheme / cursorSize: keep config/caelestia/hypr-vars.lua in sync.

let
  theme = "Bibata-Modern-Classic";
  size = 24;
in
{
  environment.systemPackages = [ pkgs.bibata-cursors ];

  environment.sessionVariables = {
    XCURSOR_THEME = theme;
    XCURSOR_SIZE = toString size;
    HYPRCURSOR_SIZE = toString size; # no hyprcursor build of Bibata: Hyprland uses the XCursor one
  };

  # System defaults: `gsettings set` (or the GNOME settings) still override them per user.
  programs.dconf = {
    enable = true;
    profiles.user.databases = [{
      settings."org/gnome/desktop/interface" = {
        cursor-theme = theme;
        cursor-size = lib.gvariant.mkInt32 size;
      };
    }];
  };

  # Only read when SDDM is the login screen (desktop.displayManager, see desktop/default.nix)
  services.displayManager.sddm.settings.Theme = {
    CursorTheme = theme;
    CursorSize = size; # kwin (SDDM's compositor) already scales it by the output scale
  };
}
