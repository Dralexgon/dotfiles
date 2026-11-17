{ config, lib, pkgs, ... }:

# Every font of the config.

let
  desktop = config.desktop;
in
{
  fonts.packages = with pkgs; [
    # Kitty: set its font to "JetBrains Mono Nerd Font Mono" for the nerd font icons
    jetbrains-mono
  ]
  # Caelestia shell
  ++ lib.optional (lib.elem "caelestia" desktop.enabled) nerd-fonts.jetbrains-mono
  # SDDM "rice" login theme (themes/sddm)
  ++ lib.optionals (desktop.enabled != [ ] && desktop.displayManager == "sddm") [ cinzel quicksand ];

  # fonts.fontDir.enable = true;
}
