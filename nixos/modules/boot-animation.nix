{ config, pkgs, lib, inputs, ... }:

let
  nvidia = lib.elem "nvidia" config.services.xserver.videoDrivers;

  # Boot animation from adi1090x-plymouth-themes. Previews: https://github.com/adi1090x/plymouth-themes
  # Red ones: red_loader, hexagon_red, flame, dragon. All 80 available themes:
  #   abstract_ring abstract_ring_alt alienware angular angular_alt black_hud blockchain circle
  #   circle_alt circle_flow circle_hud circuit colorful colorful_loop colorful_sliced connect
  #   cross_hud cubes cuts cuts_alt cyanide cybernetic dark_planet darth_vader deus_ex dna double
  #   dragon flame glitch glowing green_blocks green_loader hexa_retro hexagon hexagon_2 hexagon_alt
  #   hexagon_dots hexagon_dots_alt hexagon_hud hexagon_red hud hud_2 hud_3 hud_space ibm
  #   infinite_seal ironman liquid loader loader_2 loader_alt lone metal_ball motion optimus owl pie
  #   pixels polaroid red_loader rings rings_2 rog rog_2 seal seal_2 seal_3 sliced sphere spin
  #   spinner_alt splash square square_hud target target_2 tech_a tech_b unrap
  # (the list lives in nixpkgs: pkgs/by-name/ad/adi1090x-plymouth-themes/shas.nix)
  theme = "red_loader";
in
{
  # This module is used to configure the boot animation.

  # It's the beautiful animation that appears when you start your computer
  # and displays the manufacturer's logo with the distribution's logo.

  boot.plymouth = {
    enable = true;
    # Without `theme`, plymouth falls back to bgrt and the theme package is never used.
    inherit theme;
    themePackages = [ (pkgs.adi1090x-plymouth-themes.override { selected_themes = [ theme ]; }) ];
  };

  # Silent boot: kernel and systemd messages are otherwise drawn over the animation.
  boot.consoleLogLevel = 3;
  boot.kernelParams = [
    "quiet"
    "splash"
    "udev.log_level=3"
    "rd.udev.log_level=3"
    "systemd.show_status=auto"
    "rd.systemd.show_status=auto"
  ] ++ lib.optionals nvidia [
    # Give plymouth a real NVIDIA framebuffer instead of simpledrm.
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
  ];

  # Load the NVIDIA driver in the initrd. Otherwise it loads in stage 2, takes the screen over from
  # simpledrm mid animation, and plymouth freezes, flickers or disappears.
  boot.initrd.kernelModules = lib.mkIf nvidia [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
}
