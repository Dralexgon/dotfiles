{ pkgs, quickshell }:

# bat-swarm: bats flying across every screen, the vampire rice's transition, played by set_rice()
# (config/caelestia/hypr-user.lua). A Quickshell overlay (shell.qml) that quits by itself.
# Runs the source in the dotfiles checkout when there is one, so editing it needs no rebuild
# (like rice-picker). The store copy is only a fallback.
let
  fallback = pkgs.runCommand "bat-swarm-src" { } ''
    mkdir -p $out
    cp ${./shell.qml} $out/shell.qml
    cp ${../../themes/assets/simple-bat.svg} $out/simple-bat.svg
  '';
in
pkgs.writeShellScriptBin "bat-swarm" ''
  dotfiles="''${BAT_SWARM_DOTFILES:-$HOME/dotfiles}"
  if [ -f "$dotfiles/tools/bat-swarm/shell.qml" ]; then
    qml="$dotfiles/tools/bat-swarm/shell.qml"
    svg="$dotfiles/themes/assets/simple-bat.svg"
  else
    qml=${fallback}/shell.qml
    svg=${fallback}/simple-bat.svg
  fi
  # A new switch while a swarm is still flying replaces it rather than stacking a second one
  ${pkgs.procps}/bin/pkill -f -- "-p $qml" 2>/dev/null
  export BAT_SWARM_SVG="$svg"
  exec ${quickshell}/bin/qs -p "$qml" >/dev/null 2>&1
''
