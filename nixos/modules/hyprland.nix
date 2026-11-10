{ pkgs, ... }:

let
  # Custom QML greeter: blood drips, Predatoria crest, bleeding password field, eyelids on login
  sddm-predatoria = pkgs.runCommand "sddm-predatoria-theme" { } ''
    mkdir -p $out/share/sddm/themes
    cp -r ${../../themes/sddm/predatoria} $out/share/sddm/themes/predatoria
    chmod u+w $out/share/sddm/themes/predatoria
    cp ${../../themes/sddm/vampire.jpg} $out/share/sddm/themes/predatoria/background.jpg
  '';
in
{
  # Vampire login screen: custom "predatoria" QML theme (themes/sddm/predatoria)
  # Previous tries (see git history): sddm-astronaut recolored with the caelestia
  # "vampire" scheme, and ly with a blood red DOOM fire.
  services.displayManager.sddm = {
    enable = true;
    package = pkgs.kdePackages.sddm; # the theme is Qt6
    wayland.enable = true;
    # weston (the default) shows no mouse pointer on NVIDIA; kwin does
    wayland.compositor = "kwin";
    theme = "predatoria";
    settings.Theme = {
      CursorTheme = "Bibata-Modern-Classic"; # sweet-cursors (Hyprland's) isn't in nixpkgs
      CursorSize = 24; # kwin already scales it by the 4K output scale
    };
  };
  services.displayManager.defaultSession = "hyprland-uwsm";

  # services.displayManager.gdm.enable = true;

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

  environment.systemPackages = with pkgs; [
    sddm-predatoria
    bibata-cursors # SDDM pointer
  ];

  fonts.packages = [ pkgs.cinzel ];
}
