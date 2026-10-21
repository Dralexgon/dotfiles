{ inputs, pkgs, ... }:

let
  # older way: nixpkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
  pkgs-stable = import inputs.nixpkgs-stable { system = pkgs.system; config.allowUnfree = true; };
  # use it as pkgs-stable.example
in
{
  # services.displayManager.sddm = {
  #   enable = true;

  #   # Enables experimental Wayland support
  #   wayland.enable = true;

  #   theme = "sddm-astronaut-theme";
  # };
  services.displayManager.ly.enable = true;
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
