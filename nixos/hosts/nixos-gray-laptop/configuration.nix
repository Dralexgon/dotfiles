# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, config, ... }:

{
  networking.hostName = "nixos-gray-laptop";

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix


    # You probably shouldn't remove it
    ./../../core.nix

    # Modules: comment a line out to disable it (or use `nixcfg`)
    # ./../../modules/auto-update.nix
    # ./../../modules/boot-animation.nix
    ./../../modules/caelestia.nix

    ./../../modules/epita/core.nix

    # ./../../modules/file-transfer.nix
    # ./../../modules/flatpak.nix

    ./../../modules/gaming/core.nix

    ./../../modules/gnome.nix
    ./../../modules/hyprland.nix
    # ./../../modules/hyprland-utils.nix
    # ./../../modules/kde-plasma.nix
    # ./../../modules/latest-kernel.nix
    # ./../../modules/life-manager.nix
    # ./../../modules/llm.nix
    ./../../modules/dev/core.nix
    # ./../../modules/nix.nix
    # ./../../modules/nvidia-drivers.nix
    # ./../../modules/passwordless-rebuild.nix
    # ./../../modules/quality-of-life.nix
    # ./../../modules/quickshell.nix
    # ./../../modules/razer.nix
    ./../../modules/ricing.nix
    ./../../modules/ricing-tools.nix
    # ./../../modules/secure-boot.nix
    # ./../../modules/ssh.nix
    ./../../modules/swap.nix
    # ./../../modules/theme-catpuccin.nix
    # ./../../modules/troubleshooting.nix
    ./../../modules/useful-apps.nix
    # ./../../modules/vm.nix
    # ./../../modules/wayfire.nix
    # ./../../modules/windows.nix
  ];
 
  # Configure console keymap
  console.keyMap = "fr";

  services.xserver = {
    xkb = {
      layout = "fr";
      variant = "";
    };
  };

  # boot.extraModulePackages = [ config.boot.kernelPackages.rtl88x2bu ]; # specific driver for my wifi card

  # Packages for this host only
  environment.systemPackages = with pkgs; [
  ];

  # NixOS release this host was installed with: keep it, even after upgrades
  # (read `man configuration.nix` before changing it).
  system.stateVersion = "24.11";
}
