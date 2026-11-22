{ pkgs }:

let
  lib = pkgs.lib;

  bin = pkgs.rustPlatform.buildRustPackage {
    pname = "nixcfg";
    version = "2.0.0";
    # Only the Rust sources: editing legacy/ or the README rebuilds nothing.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./src ];
    };
    cargoLock.lockFile = ./Cargo.lock;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    # tmux keeps nixcfg running when its window is closed; libnotify tells
    # when an update or rebuild finished.
    postInstall = ''
      wrapProgram $out/bin/nixcfg --prefix PATH : ${lib.makeBinPath [ pkgs.git pkgs.tmux pkgs.libnotify ]}
    '';
    meta.mainProgram = "nixcfg";
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
  # The original Python version, kept to fall back on (nix run ~/dotfiles#nixcfg-legacy)
  # and to check this one against (compare.py).
  passthru.legacy = import ./legacy { inherit pkgs; };
  meta.mainProgram = "nixcfg";
}
