# Hyprland plugin drawing the mouse pointer trail (see main.cpp).
# Built against pkgs.hyprland, so it must match the running Hyprland: rebuild after updates.
{ pkgs }:

pkgs.hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "cursortrail";
  version = "1.0";
  src = ./.;
  nativeBuildInputs = with pkgs; [ cmake pkg-config ];
  meta.description = "Fading trail behind the mouse pointer, drawn in the Hyprland render pass";
}
