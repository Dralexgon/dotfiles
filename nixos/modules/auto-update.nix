{ config, username, ... }:

# Rebuilds this host from ~/dotfiles every night (04:40) with the newest nixos-unstable.
# The lock file isn't written (it would be root-owned in the repo), so a manual rebuild
# goes back to the locked nixpkgs until `nix flake update` (or `u` in nixcfg).
# Logs: journalctl -u nixos-upgrade
{
  system.autoUpgrade = {
    enable = true;
    flake = "/home/${username}/dotfiles#${config.networking.hostName}";
    flags = [ "--update-input" "nixpkgs" "--no-write-lock-file" ];
  };
}
