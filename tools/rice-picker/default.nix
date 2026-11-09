{ pkgs }:

let
  python = pkgs.python3.withPackages (p: [ p.pygobject3 ]);

  # Runs the source in the dotfiles checkout when there is one, so editing the
  # picker needs no rebuild (like keybinds-viewer). The store copy is only a fallback.
  # wrapGAppsHook4 gives the script the GTK4 typelibs.
  bin = pkgs.stdenvNoCC.mkDerivation {
    name = "rice-picker-bin";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.wrapGAppsHook4 pkgs.gobject-introspection ];
    buildInputs = [ pkgs.gtk4 ];
    installPhase = ''
      mkdir -p $out/bin
      cat > $out/bin/rice-picker <<EOF
      #!${pkgs.runtimeShell}
      src="\''${RICE_PICKER_DOTFILES:-\$HOME/dotfiles}/tools/rice-picker"
      [ -f "\$src/rice_picker.py" ] || src=${./.}
      exec ${python}/bin/python3 "\$src/rice_picker.py" "\$@"
      EOF
      chmod +x $out/bin/rice-picker
    '';
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "dev.dralexgon.RicePicker"; # the window's app id, so the launcher and the window match
    desktopName = "Rices";
    genericName = "Theme switcher";
    comment = "Switch between the adaptive, petals and vampire rices";
    exec = "${bin}/bin/rice-picker";
    icon = "preferences-desktop-theme";
    startupWMClass = "dev.dralexgon.RicePicker";
    categories = [ "Settings" "DesktopSettings" ];
    keywords = [ "rice" "theme" "scheme" "colors" "vampire" "petals" "adaptive" "predatoria" ];
  };
in
pkgs.symlinkJoin {
  name = "rice-picker";
  paths = [ bin desktopItem ];
  meta.mainProgram = "rice-picker";
}
