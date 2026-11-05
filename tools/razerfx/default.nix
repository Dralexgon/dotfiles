{ pkgs }:

let
  # Also used by the dev shell (flake.nix).
  pythonPackages = p: [ p.openrazer p.evdev p.numpy p.textual p.dbus-fast ];
  python = pkgs.python3.withPackages pythonPackages;

  bin = pkgs.writeShellApplication {
    name = "razerfx";
    # pw-record captures audio for the visualisers, wpctl reads the mic mute,
    # gpu-screen-recorder + ffmpeg capture the screen for the screen mirror
    # (gsr finds its KMS helper in /run/wrappers, see razer.nix).
    runtimeInputs = with pkgs; [ pipewire wireplumber systemd gpu-screen-recorder ffmpeg-headless ];
    # Like nixcfg: runs the source in the dotfiles checkout when there is one,
    # so editing razerfx needs no rebuild (restart the daemon: r in the TUI).
    text = ''
      src="''${RAZERFX_DOTFILES:-$HOME/dotfiles}/tools/razerfx"
      [ -f "$src/razerfx.py" ] || src=${./.}
      exec ${python}/bin/python "$src/razerfx.py" "$@"
    '';
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "razerfx";
    desktopName = "razerfx";
    genericName = "Keyboard effects";
    comment = "Pick the lighting effect of the Razer keyboard";
    exec = "${pkgs.kitty}/bin/kitty --class razerfx --title razerfx ${bin}/bin/razerfx";
    icon = "input-keyboard";
    categories = [ "System" "Settings" ];
    keywords = [ "razer" "rgb" "keyboard" "lighting" "effects" ];
  };
in
pkgs.symlinkJoin {
  name = "razerfx";
  paths = [ bin desktopItem ];
  passthru = { inherit pythonPackages; };
  meta.mainProgram = "razerfx";
}
