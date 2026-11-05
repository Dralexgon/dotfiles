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

  # openrazer copies its .ko files without `make modules_install`, so kbuild
  # never runs kmodigest on them and the module aggregator fails on the
  # missing .ko.cer files. Generate them ourselves.
  nixpkgs.overlays = [
    (final: prev: {
      kernelPackagesExtensions = prev.kernelPackagesExtensions ++ [
        (kfinal: kprev: {
          openrazer = kprev.openrazer.overrideAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              for ko in "$binDir"/*.ko; do
                ${lib.getExe final.buildPackages.kmodigest} "$ko"
              done
            '';
          });
        })
      ];
    })
  ];

  hardware.openrazer = {
    enable = true;
    users = ["alex"];
  };

  users.users."alex" = { extraGroups = [ "openrazer" ]; };
}
