{ pkgs }:

let
  # Also used by the dev shell (flake.nix), which adds textual-dev.
  pythonPackages = p: [ p.textual p.dbus-fast ];
  python = pkgs.python3.withPackages pythonPackages;

  bin = pkgs.writeShellApplication {
    name = "nixcfg";
    # tmux keeps nixcfg running when its window is closed; libnotify tells
    # when an update or rebuild finished.
    runtimeInputs = [ pkgs.git pkgs.tmux pkgs.libnotify ];
    # Runs the source in the dotfiles checkout when there is one, so editing
    # nixcfg needs no rebuild. The store copy is only a fallback; a rebuild
    # is still needed when the Python packages change.
    text = ''
      src="''${NIXCFG_DOTFILES:-$HOME/dotfiles}/tools/nixcfg"
      [ -f "$src/nixcfg.py" ] || src=${./.}
      exec ${python}/bin/python "$src/nixcfg.py" "$@"
    '';
  };

  # Shows nixcfg in app launchers (Caelestia, rofi...). It opens in kitty
  # instead of Terminal=true, so it does not depend on the launcher's terminal.
  desktopItem = pkgs.makeDesktopItem {
    name = "nixcfg";
    desktopName = "nixcfg";
    genericName = "NixOS configuration";
    comment = "Toggle modules and packages of this host";
    exec = "${pkgs.kitty}/bin/kitty --class nixcfg --title nixcfg ${bin}/bin/nixcfg";
    icon = "nix-snowflake";
    categories = [ "System" "Settings" ];
    keywords = [ "nix" "nixos" "config" "packages" "modules" ];
  };
in
pkgs.symlinkJoin {
  name = "nixcfg";
  paths = [ bin desktopItem ];
  passthru = { inherit pythonPackages; };
  meta.mainProgram = "nixcfg";
}
