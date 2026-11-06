{ inputs, pkgs, ... }:

let
  # older way: nixpkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
  pkgs-stable = import inputs.nixpkgs-stable { system = pkgs.stdenv.hostPlatform.system; config.allowUnfree = true; };
  # use it as pkgs-stable.example
in
{
  # services.displayManager.sddm = {
  #   enable = true;

  #   # Enables experimental Wayland support
  #   wayland.enable = true;

  #   theme = "sddm-astronaut-theme";
  # };
  # Vampire login screen: blood red DOOM fire behind the ly box
  services.displayManager.ly = {
    enable = true;
    settings = {
      animation = "doom";
      doom_top_color = "0x00300000"; # flame tips (low intensity): dried blood
      doom_middle_color = "0x00A00000"; # crimson
      doom_bottom_color = "0x00FF2020"; # fire base (high intensity): bright blood
      doom_fire_height = 6; # 1 thru 9
      border_fg = "0x00B00000";
      fg = "0x00E8DCCB"; # bone white text
      bigclock = "en";
    };
  };
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
    kitty # Hyprland console
  ];
}
