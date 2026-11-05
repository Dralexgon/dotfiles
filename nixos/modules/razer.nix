{ config, pkgs, lib, inputs, ... }:

let
  razerfx = import ../../tools/razerfx { inherit pkgs; };
in
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

    # TUI + daemon for the keyboard effects (tools/razerfx)
    razerfx
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

  # openrazer: also lets razerfx read key presses (openrazer's udev rule
  # gives the Razer /dev/input devices to this group)
  users.users."alex" = { extraGroups = [ "openrazer" ]; };

  # The razerfx screen mirror captures the screen on the GPU with
  # gpu-screen-recorder. This gives its KMS helper the capability to do it
  # without asking for root (a setcap wrapper), which a service can't answer.
  programs.gpu-screen-recorder.enable = true;

  # The razerfx render loop, which follows ~/.local/state/razerfx/state.json
  # and the Caelestia scheme. Logs: journalctl --user -u razerfx
  systemd.user.services.razerfx = {
    description = "Razer keyboard effects (razerfx)";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" "openrazer-daemon.service" ];
    wants = [ "openrazer-daemon.service" ];
    serviceConfig = {
      ExecStart = "${lib.getExe razerfx} daemon";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
