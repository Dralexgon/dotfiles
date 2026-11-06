{ config, pkgs, lib, inputs, ... }:

let
  nvidia = lib.elem "nvidia" config.services.xserver.videoDrivers;
in
{
  # This module is used to configure the boot animation.

  # It's the beautiful animation that appears when you start your computer
  # and displays the manufacturer's logo with the distribution's logo.

  boot.plymouth = {
    enable = true;
    # Without `theme`, plymouth falls back to bgrt and the theme package is never used.
    # Red spinning loader on black, to match the vampire rice. Previews:
    # https://github.com/adi1090x/plymouth-themes
    theme = "red_loader";
    themePackages = [ (pkgs.adi1090x-plymouth-themes.override { selected_themes = [ "red_loader" ]; }) ];
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
