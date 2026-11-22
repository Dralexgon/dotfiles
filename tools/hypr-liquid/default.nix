# hyprliquid: Liquid Glass, Acrylic, Mica and Aero material effects (github:zaregototsukai/hyprliquid).
# Built against pkgs.hyprland, so it must match the running Hyprland: rebuild after updates.
{ pkgs, src }:

pkgs.hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprliquid";
  version = "0.3.0";
  inherit src;
  nativeBuildInputs = with pkgs; [ cmake pkg-config hyprwayland-scanner ];
  buildInputs = with pkgs; [ stb systemd ];
  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];
  meta = {
    description = "Liquid Glass, Acrylic, Mica and Aero material effects for Hyprland";
    homepage = "https://github.com/zaregototsukai/hyprliquid";
    license = pkgs.lib.licenses.bsd3;
  };
}
