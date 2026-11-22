{ pkgs }:

# installer-gui: install.sh in a window (GTK4 + libadwaita), see installer_gui.py.
# Started by `./install.sh --gui` (through `nix run ~/dotfiles#installer-gui` when it
# isn't installed, e.g. on a fresh NixOS). wrapGAppsHook4 gives the script the typelibs.
let
  python = pkgs.python3.withPackages (p: [ p.pygobject3 ]);
in
pkgs.stdenvNoCC.mkDerivation {
  name = "installer-gui";
  src = ./.;
  nativeBuildInputs = [ pkgs.wrapGAppsHook4 pkgs.gobject-introspection ];
  buildInputs = [ pkgs.gtk4 pkgs.libadwaita ];
  installPhase = ''
    mkdir -p $out/bin $out/share/installer-gui
    cp installer_gui.py $out/share/installer-gui/
    cat > $out/bin/installer-gui <<SH
    #!${pkgs.runtimeShell}
    export INSTALLER_GUI_ASKPASS=$out/bin/installer-gui-askpass
    exec ${python}/bin/python3 $out/share/installer-gui/installer_gui.py "\$@"
    SH
    cat > $out/bin/installer-gui-askpass <<SH
    #!${pkgs.runtimeShell}
    exec ${python}/bin/python3 $out/share/installer-gui/installer_gui.py --askpass "\$@"
    SH
    chmod +x $out/bin/*
  '';
  meta.mainProgram = "installer-gui";
}
