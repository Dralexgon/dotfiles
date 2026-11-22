{ config, lib, pkgs, ... }:

# Wayfire (desktop.enabled, see default.nix)
lib.mkIf (lib.elem "wayfire" config.desktop.enabled) {
  programs.wayfire = {
    enable = true;
    plugins = with pkgs.wayfirePlugins; [
      wcm
      wf-shell
      wayfire-plugins-extra
    ];
  };

  # programs.uwsm.enable = true; # Allow wayfire to be selected from the display_manager (login screen)
}