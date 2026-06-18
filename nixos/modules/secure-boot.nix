{ lib, pkgs, ... }:

{
  # # Enable that first
  # boot.loader.limine.enable = true;
  # # Then run sudo sbctl create-keys
  # # Then :
  # # Enable UEFI Secure Boot Setup Mode
  # # This usually involves entering the UEFI firmware menu (BIOS) and enabling the relevant option under Secure Boot named "Reset to Setup Mode" or "Erase all Secure Boot settings".
  # # On some UEFI firmware implementations, there is not an explicit option to enter Setup Mode, instead the user must chose the option(s) to erase existing Secure Boot keys.

  # # Then enable this :
  # boot.loader.limine.secureBoot.enable = true;


  environment.systemPackages = with pkgs; [
    sbctl
    niv
  ];
}