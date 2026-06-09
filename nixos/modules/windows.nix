{ config, pkgs, ... }:

{
  # Sync clock with windows dual boot
  time.hardwareClockInLocalTime = true;

  nix.gc.automatic = true;
  # nix.gc.options = ["--delete-older-than 30d"];
  boot.loader.systemd-boot.configurationLimit = 2;
}