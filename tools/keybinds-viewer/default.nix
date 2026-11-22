{ pkgs }:

let
  python = pkgs.python3.withPackages (p: [ p.pygobject3 ]);

  # Runs the source in the dotfiles checkout when there is one, so editing the
  # viewer needs no rebuild (like nixcfg). The store copy is only a fallback.
  # wrapGAppsHook4 gives the script the GTK4 / WebKitGTK typelibs and modules.
  bin = pkgs.stdenvNoCC.mkDerivation {
    name = "keybinds-viewer-bin";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.wrapGAppsHook4 pkgs.gobject-introspection ];
    buildInputs = [ pkgs.gtk4 pkgs.webkitgtk_6_0 pkgs.glib-networking ];
    installPhase = ''
      mkdir -p $out/bin
      cat > $out/bin/keybinds-viewer <<EOF
      #!${pkgs.runtimeShell}
      src="\''${KEYBINDS_VIEWER_DOTFILES:-\$HOME/dotfiles}/tools/keybinds-viewer"
      [ -f "\$src/keybinds_viewer.py" ] || src=${./.}
      exec ${python}/bin/python3 "\$src/keybinds_viewer.py" "\$@"
      EOF
      chmod +x $out/bin/keybinds-viewer
    '';
    preFixup = ''
      gappsWrapperArgs+=(--prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]})
    '';
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "dev.dralexgon.KeybindsViewer"; # the window's app id, so the launcher and the window match
    desktopName = "Keybinds";
    genericName = "Keyboard shortcuts";
    comment = "See every Hyprland shortcut on a drawing of the keyboard";
    exec = "${bin}/bin/keybinds-viewer";
    icon = "preferences-desktop-keyboard-shortcuts";
    startupWMClass = "dev.dralexgon.KeybindsViewer";
    categories = [ "System" "Utility" ];
    keywords = [ "keybinds" "shortcuts" "hotkeys" "keyboard" "hyprland" ];
  };
in
pkgs.symlinkJoin {
  name = "keybinds-viewer";
  paths = [ bin desktopItem ];
  meta.mainProgram = "keybinds-viewer";
}
