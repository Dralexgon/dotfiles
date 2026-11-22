# Hyprland plugin animating closing / opening windows: petals blown by the wind or blood
# draining off them (see main.cpp).
# Built against pkgs.hyprland, so it must match the running Hyprland: rebuild after updates.
{ pkgs }:

pkgs.hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "windowfx";
  version = "1.1";
  src = ./.;
  nativeBuildInputs = with pkgs; [ cmake pkg-config ];
  meta.description = "Closing windows shatter into petals or drain away in blood, opening ones assemble back";
}
