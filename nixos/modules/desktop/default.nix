{ config, lib, pkgs, ... }:

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

  # Custom QML greeter: blood drips, Predatoria crest, bleeding password field, eyelids on login
  sddm-predatoria = pkgs.runCommand "sddm-predatoria-theme" { } ''
    mkdir -p $out/share/sddm/themes
    cp -r ${../../../themes/sddm/predatoria} $out/share/sddm/themes/predatoria
    chmod u+w $out/share/sddm/themes/predatoria
    cp ${../../../themes/sddm/vampire.jpg} $out/share/sddm/themes/predatoria/background.jpg
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
      description = "The login screen: SDDM with the predatoria theme, or GNOME's GDM.";
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

    # Vampire login screen: custom "predatoria" QML theme (themes/sddm/predatoria)
    # Previous tries (see git history): sddm-astronaut recolored with the caelestia
    # "vampire" scheme, and ly with a blood red DOOM fire.
    (lib.mkIf (cfg.displayManager == "sddm") {
      services.displayManager.sddm = {
        enable = true;
        package = lib.mkDefault pkgs.kdePackages.sddm; # the theme is Qt6 (Plasma sets its own)
        wayland.enable = true;
        # weston (the default) shows no mouse pointer on NVIDIA; kwin does
        wayland.compositor = "kwin";
        theme = "predatoria";
        settings.Theme = {
          CursorTheme = "Bibata-Modern-Classic"; # sweet-cursors (Hyprland's) isn't in nixpkgs
          CursorSize = 24; # kwin already scales it by the 4K output scale
        };
      };

      environment.systemPackages = with pkgs; [
        sddm-predatoria
        bibata-cursors # SDDM pointer
      ];

      fonts.packages = [ pkgs.cinzel ];
    })
  ]);
}
