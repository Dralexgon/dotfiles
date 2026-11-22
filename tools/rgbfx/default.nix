{ pkgs }:

let
  # Also used by the dev shell (flake.nix).
  pythonPackages = p: [ p.openrazer p.evdev p.numpy p.textual p.dbus-fast p.openrgb-python ];
  python = pkgs.python3.withPackages pythonPackages;

  bin = pkgs.writeShellApplication {
    name = "rgbfx";
    # pw-record captures audio for the visualisers, wpctl reads the mic mute,
    # gpu-screen-recorder + ffmpeg capture the screen for the screen mirror
    # (gsr finds its KMS helper in /run/wrappers, see razer.nix).
    runtimeInputs = with pkgs; [ pipewire wireplumber systemd gpu-screen-recorder ffmpeg-headless ];
    # Like nixcfg: runs the source in the dotfiles checkout when there is one,
    # so editing rgbfx needs no rebuild (restart the daemon: r in the TUI).
    text = ''
      src="''${RGBFX_DOTFILES:-$HOME/dotfiles}/tools/rgbfx"
      [ -f "$src/rgbfx.py" ] || src=${./.}
      exec ${python}/bin/python "$src/rgbfx.py" "$@"
    '';
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "rgbfx";
    desktopName = "rgbfx";
    genericName = "RGB effects";
    comment = "Pick the lighting effect of the Razer keyboard and the case fans";
    exec = "${pkgs.kitty}/bin/kitty --class rgbfx --title rgbfx ${bin}/bin/rgbfx";
    icon = "input-keyboard";
    categories = [ "System" "Settings" ];
    keywords = [ "razer" "rgb" "keyboard" "fans" "openrgb" "lighting" "effects" ];
  };
in
pkgs.symlinkJoin {
  name = "rgbfx";
  paths = [ bin desktopItem ];
  passthru = { inherit pythonPackages; };
  meta.mainProgram = "rgbfx";
}
