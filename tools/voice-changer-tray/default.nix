{ pkgs }:

# Tray icon for the voice changer (Applio, github:Dralexgon/nix-voice-changer):
# starts it in the background, Open web UI / Show logs / Quit from the tray.
# `applio` itself comes from programs.voice-changer (on PATH).
let
  lib = pkgs.lib;
  python = pkgs.python3.withPackages (p: [ p.pygobject3 ]);

  bin = pkgs.stdenv.mkDerivation {
    pname = "voice-changer-tray";
    version = "1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.wrapGAppsHook3 pkgs.gobject-introspection ];
    buildInputs = [ pkgs.gtk3 pkgs.libayatana-appindicator ];
    installPhase = ''
      install -Dm644 ${./tray.py} $out/share/voice-changer-tray/tray.py
      mkdir -p $out/bin
      makeWrapper ${python}/bin/python3 $out/bin/voice-changer-tray \
        --add-flags "-I $out/share/voice-changer-tray/tray.py" \
        --prefix PATH : ${lib.makeBinPath [ pkgs.kitty pkgs.libnotify pkgs.xdg-utils pkgs.coreutils ]}
    '';
    # wrapGAppsHook3 adds GI_TYPELIB_PATH etc. to the wrapper above
    meta.mainProgram = "voice-changer-tray";
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "voice-changer";
    desktopName = "Voice Changer";
    genericName = "AI voice changer (Applio)";
    comment = "Real-time RVC voice changer, outputs to the Voice Changer Mic";
    exec = "${bin}/bin/voice-changer-tray";
    icon = "audio-input-microphone";
    categories = [ "AudioVideo" "Audio" ];
    keywords = [ "voice" "changer" "applio" "rvc" "mic" ];
  };
in
pkgs.symlinkJoin {
  name = "voice-changer";
  paths = [ bin desktopItem ];
}
