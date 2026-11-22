# Placeholder for /etc/nixos/hardware-configuration.nix, used by configuration.nix
# only in pure evaluation (nix flake check), which can't read files outside the flake.
# It lets the default host evaluate, but the system it describes is not a real
# machine: the pre-switch check below refuses to switch to it or boot it.
{ ... }:

{
  nixpkgs.hostPlatform = "x86_64-linux";

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  system.preSwitchChecks.defaultHostNeedsImpure = ''
    echo "The default host was built with placeholder hardware (pure evaluation)." >&2
    echo "Rebuild it with --impure so /etc/nixos/hardware-configuration.nix is used." >&2
    exit 1
  '';
}
