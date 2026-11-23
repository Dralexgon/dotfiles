{ pkgs }:

let
  # Also used by the dev shell (flake.nix).
  pythonPackages = p: [ p.openrazer p.evdev p.numpy p.pygobject3 p.dbus-fast p.openrgb-python ];
  python = pkgs.python3.withPackages pythonPackages;

  # Like nixcfg: runs the source in the dotfiles checkout when there is one,
  # so editing rgbfx needs no rebuild (restart the daemon: the ⟳ button in the window).
  script = pkgs.writeShellScript "rgbfx" ''
    src="''${RGBFX_DOTFILES:-$HOME/dotfiles}/tools/rgbfx"
    [ -f "$src/rgbfx.py" ] || src=${./.}
    exec ${python}/bin/python "$src/rgbfx.py" "$@"
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "dev.dralexgon.rgbfx";
    desktopName = "rgbfx";
    genericName = "RGB effects";
    comment = "Pick the lighting effect of the Razer keyboard and the case fans";
    exec = "rgbfx";
    icon = "input-keyboard";
    startupWMClass = "dev.dralexgon.rgbfx";
    categories = [ "System" "Settings" ];
    keywords = [ "razer" "rgb" "keyboard" "fans" "openrgb" "lighting" "effects" ];
  };
in
pkgs.stdenvNoCC.mkDerivation {
  name = "rgbfx";
  dontUnpack = true;
  # wrapGAppsHook4 gives the window its GTK4 / libadwaita typelibs
  nativeBuildInputs = [ pkgs.wrapGAppsHook4 pkgs.gobject-introspection ];
  buildInputs = [ pkgs.gtk4 pkgs.libadwaita ];
  installPhase = ''
    install -Dm755 ${script} $out/bin/rgbfx
    mkdir -p $out/share
    cp -r ${desktopItem}/share/applications $out/share/
  '';
  # pw-record captures audio for the visualisers, wpctl reads the mic mute,
  # gpu-screen-recorder + ffmpeg capture the screen for the screen mirror
  # (gsr finds its KMS helper in /run/wrappers, see razer.nix).
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${pkgs.lib.makeBinPath (with pkgs; [
      pipewire wireplumber systemd gpu-screen-recorder ffmpeg-headless
    ])})
  '';
  passthru = { inherit pythonPackages; };
  meta.mainProgram = "rgbfx";
}
