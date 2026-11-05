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

    # Sets the Razer lighting to the Caelestia primary, called by apply-scheme.sh
    (writers.writePython3Bin "caelestia-razer-colour" {
      libraries = with python3Packages; [ openrazer ];
      flakeIgnore = [ "E203" "E501" ];
    } (builtins.readFile ../../config/caelestia/razer-colour.py))
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
