{ pkgs, ... }:

{
  # OpenRGB: GUI + daemon for the motherboard / case RGB
  # (Gigabyte RGB Fusion 2 USB controller, ARGB headers, RAM over SMBus)
  # The case fans show the keyboard effect, drawn by rgbfx through its SDK server
  # (tools/rgbfx/fans.py, razer.nix).
  services.hardware.openrgb = {
    enable = true;
    package = pkgs.openrgb-with-all-plugins;
    motherboard = "amd"; # loads i2c-piix4 for SMBus devices (RAM, etc.)
  };
}
