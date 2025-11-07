{ config, pkgs, lib, inputs, ... }:

{
  environment.systemPackages = with pkgs; [
    # GUI to manage rgb
    polychromatic
    openrazer-daemon
    (python313.withPackages (ps: with ps; [
      numpy
      matplotlib
      scipy
      pygame
      pyaudio
    ]))
  ];

  hardware.openrazer = {
    enable = true;
    users = ["alex"];
  };

  users.users."alex" = { extraGroups = [ "openrazer" ]; };
}
