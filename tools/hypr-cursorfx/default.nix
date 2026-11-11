# Hyprland plugin throwing petals, blood drops or images behind the mouse pointer (see main.cpp).
# Built against pkgs.hyprland, so it must match the running Hyprland: rebuild after updates.
{ pkgs }:

pkgs.hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "cursorfx";
  version = "1.0";
  src = ./.;
  nativeBuildInputs = with pkgs; [ cmake pkg-config ];
  buildInputs = [ pkgs.cairo ];
  meta.description = "Petals, blood drops or images thrown behind the mouse pointer";
}
