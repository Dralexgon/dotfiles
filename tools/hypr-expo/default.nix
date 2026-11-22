# hyprexpo: workspace overview plugin, ported to the running Hyprland (see README.md).
# Built against pkgs.hyprland, so it must match the running Hyprland: rebuild after updates.
{ pkgs }:

pkgs.hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprexpo";
  version = "0.57.1";
  src = ./.;
  nativeBuildInputs = with pkgs; [ cmake pkg-config ];
  meta = {
    description = "Workspace overview for Hyprland, ported from hyprwm/hyprland-plugins";
    license = pkgs.lib.licenses.bsd3;
  };
}
