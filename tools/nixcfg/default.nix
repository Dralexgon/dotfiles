{ pkgs }:

let
  python = pkgs.python3.withPackages (p: [ p.textual ]);

  bin = pkgs.writeShellApplication {
    name = "nixcfg";
    runtimeInputs = [ pkgs.git ];
    text = ''
      exec ${python}/bin/python ${./.}/nixcfg.py "$@"
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
  meta.mainProgram = "nixcfg";
}
