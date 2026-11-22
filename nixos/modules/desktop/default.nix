{ config, lib, pkgs, username, ... }:

# Desktops (desktop environments, window managers, shells), chosen per host:
#
#   desktop.enabled = [ "caelestia" "gnome" ];  # all selectable on the login screen
#   desktop.defaultSession = "caelestia";       # preselected (default: the first one)
#
# Imported by core.nix, so every host has these options. Each desktop is a file of
# this folder wrapped in `lib.mkIf (lib.elem "<name>" config.desktop.enabled)`.
# To add one: create <name>.nix like the others and add its session below.
# nixcfg shows them as the "desktop" group and edits the host's desktop.enabled.

let
  cfg = config.desktop;
  has = name: lib.elem name cfg.enabled;

  # Desktop -> its session name on the login screen
  # (ls /run/current-system/sw/share/{wayland-,x}sessions)
  sessions = {
    caelestia = "hyprland-uwsm"; # the Caelestia shell runs on Hyprland
    gnome = "gnome";
    hyprland = "hyprland-uwsm";
    kde = "plasma";
    wayfire = "wayfire";
  };
  names = builtins.attrNames sessions;

  # Custom QML greeters, both in the "rice" theme that shows the one of the current rice:
  # - predatoria (vampire): blood drips, Predatoria crest, bleeding password field, eyelids on login
  # - petals: falling petals, a flower blooming behind the avatar, blossom password dots, petal
  #   burst on login (the twin of the petals lock screen, sharing its PetalShape.qml)
  sddm-rice = pkgs.runCommand "sddm-rice-theme" { } ''
    t=$out/share/sddm/themes/rice
    mkdir -p $t
    cp ${../../../themes/sddm/rice}/* $t/
    cp -r ${../../../themes/sddm/predatoria} $t/predatoria
    cp -r ${../../../themes/sddm/petals} $t/petals
    chmod -R u+w $t
    cp ${../../../themes/sddm/vampire.jpg} $t/predatoria/background.jpg
    cp ${../../../themes/sddm/petals.jpg} $t/petals/background.jpg
    cp ${../../../config/caelestia/lock/PetalShape.qml} $t/petals/PetalShape.qml
  '';
in
{
  imports = map (name: ./. + "/${name}.nix") names;

  options.desktop = {
    enabled = lib.mkOption {
      type = lib.types.listOf (lib.types.enum names);
      default = [ ];
      example = [ "caelestia" "gnome" ];
      description = "Installed desktops, all selectable on the login screen.";
    };
    defaultSession = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum names);
      default = if cfg.enabled == [ ] then null else builtins.head cfg.enabled;
      defaultText = lib.literalExpression "the first of desktop.enabled";
      description = "The desktop preselected on the login screen.";
    };
    displayManager = lib.mkOption {
      type = lib.types.enum [ "sddm" "gdm" ];
      default = "sddm";
      description = "The login screen: SDDM with the rice theme (petals or predatoria), or GNOME's GDM.";
    };
  };

  config = lib.mkIf (cfg.enabled != [ ]) (lib.mkMerge [
    {
      # A throw, not an assertion: NixOS checks defaultSession (with a vaguer error) first.
      services.displayManager.defaultSession = lib.mkIf (cfg.defaultSession != null) (
        if has cfg.defaultSession then sessions.${cfg.defaultSession}
        else throw "desktop.defaultSession is \"${cfg.defaultSession}\", which isn't in desktop.enabled"
      );
      services.displayManager.gdm.enable = cfg.displayManager == "gdm";

      # GNOME and Plasma both set the SSH password prompt: keep Plasma's.
      programs.ssh.askPassword = lib.mkIf (has "gnome" && has "kde")
        (lib.mkForce "${pkgs.kdePackages.ksshaskpass.out}/bin/ksshaskpass");
    }

    # Login screen following the rice: custom "rice" QML theme (themes/sddm/rice), showing
    # themes/sddm/petals with the petals rice and themes/sddm/predatoria (vampire) otherwise.
    # Previous tries (see git history): sddm-astronaut recolored with the caelestia
    # "vampire" scheme, and ly with a blood red DOOM fire.
    (lib.mkIf (cfg.displayManager == "sddm") {
      services.displayManager.sddm = {
        enable = true;
        package = lib.mkDefault pkgs.kdePackages.sddm; # the theme is Qt6 (Plasma sets its own)
        wayland.enable = true;
        # weston (the default) shows no mouse pointer on NVIDIA; kwin does
        wayland.compositor = "kwin";
        theme = "rice"; # its pointer is set in ../cursors.nix, its fonts in ../fonts.nix
      };

      environment.systemPackages = [ sddm-rice ];

      # set_rice() (config/caelestia/hypr-user.lua) leaves the current rice's name here as an
      # empty file, for the "rice" theme: the greeter can't read the home folder.
      systemd.tmpfiles.rules = [ "d /var/lib/login-rice 0755 ${username} - -" ];
    })
  ]);
}
