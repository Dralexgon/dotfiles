{ inputs, lib, pkgs, ... }:

# Secure Boot with lanzaboote: signs the systemd-boot entries with the keys in /var/lib/sbctl.
# First setup on a new host:
#   1. Without this module, run `sudo sbctl create-keys`
#   2. Enable this module and rebuild, check with `sudo sbctl verify`
#   3. In the UEFI menu, reset Secure Boot to Setup Mode, then `sudo sbctl enroll-keys --microsoft`
#   4. Reboot with Secure Boot on, `bootctl status` shows "Secure Boot: enabled (user)"
{
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

  # Lanzaboote replaces the systemd-boot module (core.nix enables it).
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  environment.systemPackages = with pkgs; [
    sbctl # For debugging and troubleshooting Secure Boot
    niv
  ];
}
