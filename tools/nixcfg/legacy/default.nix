{ pkgs }:

# The original Python (Textual) nixcfg, kept to fall back on and to check the
# Rust version against (../compare.py). Not installed: nix run ~/dotfiles#nixcfg-legacy
let
  # Also used by the dev shell (flake.nix), which adds textual-dev.
  pythonPackages = p: [ p.textual p.dbus-fast ];
  python = pkgs.python3.withPackages pythonPackages;

  bin = pkgs.writeShellApplication {
    name = "nixcfg-legacy";
    # tmux keeps nixcfg running when its window is closed; libnotify tells
    # when an update or rebuild finished.
    runtimeInputs = [ pkgs.git pkgs.tmux pkgs.libnotify ];
    # Runs the source in the dotfiles checkout when there is one, so editing
    # it needs no rebuild. The store copy is only a fallback.
    text = ''
      src="''${NIXCFG_DOTFILES:-$HOME/dotfiles}/tools/nixcfg/legacy"
      [ -f "$src/nixcfg.py" ] || src=${./.}
      exec ${python}/bin/python "$src/nixcfg.py" "$@"
    '';
  };
in
bin.overrideAttrs (old: {
  passthru = (old.passthru or { }) // { inherit pythonPackages python; };
})
