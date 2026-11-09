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
    # ./../../modules/caelestia.nix

    ./../../modules/epita/core.nix
    # ./../../modules/epita/android.nix
    ./../../modules/epita/c.nix
    # ./../../modules/epita/cpp.nix
    ./../../modules/epita/criterion.nix
    ./../../modules/epita/docker.nix
    # ./../../modules/epita/image.nix
    # ./../../modules/epita/java.nix
    # ./../../modules/epita/js.nix
    ./../../modules/epita/latex.nix
    # ./../../modules/epita/net.nix

    # ./../../modules/file-transfer.nix
    ./../../modules/flatpak.nix
    # ./../../modules/game-creation.nix

    ./../../modules/gaming/core.nix
    ./../../modules/gaming/albion.nix
    # ./../../modules/gaming/minecraft.nix

    ./../../modules/gnome.nix
    ./../../modules/hyprland.nix
    # ./../../modules/hyprland-utils.nix
    # ./../../modules/jetbrains.nix
    # ./../../modules/kde-plasma.nix
    # ./../../modules/life-manager.nix
    # ./../../modules/llm.nix
    ./../../modules/neovim.nix
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
    # ./../../modules/troobleshooting.nix
    # ./../../modules/vm.nix
    # ./../../modules/wayfire.nix
    # ./../../modules/windows.nix
  ];

  # Packages for this host only
  environment.systemPackages = with pkgs; [
  ];
}
