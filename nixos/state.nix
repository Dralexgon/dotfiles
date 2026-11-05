# Turns a host's state.json (edited by hand or with `nix run ~/dotfiles#nixcfg`)
# into a module: imports the enabled modules and installs the listed packages.
#
# state.json:
#   "modules":  paths relative to nixos/modules, without .nix (e.g. "gnome", "epita/c")
#   "packages": nixpkgs attribute paths (e.g. "gparted", "kdePackages.kate")
#
# A folder with a core.nix is a group: its core ("epita/core") switches the
# whole group, so a submodule ("epita/c") is only imported when its core is
# enabled too. Disabling the core keeps the submodule choices for later.
stateFile:

let
  state = builtins.fromJSON (builtins.readFile stateFile);
  enabled = state.modules or [ ];

  folderOf = name:
    let m = builtins.match "(.*)/[^/]+" name;
    in if m == null then null else builtins.head m;

  isActive = name:
    let
      folder = folderOf name;
      core = "${folder}/core";
    in
    folder == null
    || name == core
    || !builtins.pathExists (./modules + "/${core}.nix")
    || builtins.elem core enabled;
in
{ lib, pkgs, ... }:

{
  imports = map (name: ./modules + "/${name}.nix") (builtins.filter isActive enabled);

  environment.systemPackages = map
    (name: lib.getAttrFromPath (lib.splitString "." name) pkgs)
    (state.packages or [ ]);
}
