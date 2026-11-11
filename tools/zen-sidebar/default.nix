{ pkgs }:

let
  python = pkgs.python3.withPackages (p: [ p.lz4 ]);
in
pkgs.writeShellApplication {
  name = "zen-sidebar";
  runtimeInputs = [ pkgs.procps ];
  # Like nixcfg/razerfx: runs the source in the dotfiles checkout when there is
  # one, so editing zen_sidebar.py needs no rebuild.
  text = ''
    src="''${ZEN_SIDEBAR_DOTFILES:-$HOME/dotfiles}/tools/zen-sidebar"
    [ -f "$src/zen_sidebar.py" ] || src=${./.}
    exec ${python}/bin/python "$src/zen_sidebar.py" "$@"
  '';
}
