# Hyprland plugin shattering closing windows into petals blown by the wind (see main.cpp).
# Built against pkgs.hyprland, so it must match the running Hyprland: rebuild after updates.
{ pkgs }:

pkgs.hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "petals";
  version = "1.0";
  src = ./.;
  nativeBuildInputs = with pkgs; [ cmake pkg-config ];
  meta.description = "Closing windows shatter into petals blown away by the wind";
}
