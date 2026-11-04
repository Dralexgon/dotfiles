{ pkgs }:

let
  python = pkgs.python3.withPackages (p: [ p.textual ]);
in
pkgs.writeShellApplication {
  name = "nixcfg";
  runtimeInputs = [ pkgs.git ];
  text = ''
    exec ${python}/bin/python ${./.}/nixcfg.py "$@"
  '';
}
