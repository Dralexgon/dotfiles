{ config, pkgs, lib, inputs, ... }:

{
  networking.hostName = "nixos";

  imports = [
    # Include the results of the hardware scan.
    /etc/nixos/hardware-configuration.nix


    # You probably shouldn't remove it
    ./../../core.nix

    # Modules: comment a line out to disable it (or use `nixcfg`)
    ./../../modules/auto-update.nix
    ./../../modules/boot-animation.nix

    ./../../modules/epita/core.nix

    # ./../../modules/file-transfer.nix
    ./../../modules/flatpak.nix

    ./../../modules/gaming/core.nix

    # ./../../modules/hyprland-utils.nix
    ./../../modules/latest-kernel.nix
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
    # ./../../modules/swap.nix
    # ./../../modules/theme-catpuccin.nix
    # ./../../modules/troubleshooting.nix
    ./../../modules/useful-apps.nix
    # ./../../modules/vm.nix
    # ./../../modules/windows.nix
  ];

  # Desktops: all selectable on the login screen (or use `nixcfg`).
  # caelestia also turns hyprland on. See nixos/modules/desktop/default.nix
  desktop.enabled = [
    # "caelestia"
    "gnome"
    "hyprland"
    # "kde"
    # "wayfire"
  ];
  desktop.defaultSession = "hyprland";

  # Packages for this host only
  environment.systemPackages = with pkgs; [
  ];

  # NixOS release this host was installed with: keep it, even after upgrades
  # (read `man configuration.nix` before changing it).
  system.stateVersion = "24.11";
}
