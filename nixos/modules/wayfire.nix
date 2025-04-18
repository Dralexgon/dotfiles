{ pkgs, ... }:

{
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