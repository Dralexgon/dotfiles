{ ... }:

# Lets admins (wheel) run `sudo nixos-rebuild` and `nh os switch/boot` without
# a password, so tools like coding agents (and nixcfg) can rebuild on their own.
# WARNING: both can build and switch to any config as root, so this is
# passwordless root for anything running as a wheel user.
let
  # nh runs its root steps as `sudo env VAR=value... <command>`, so only allow
  # those commands (a sudoers regex, sudo >= 1.9.10), not `sudo env` itself.
  system = "/nix/store/[a-z0-9]{32}-nixos-system-[^ /]+";
  envVars = "((USER|PATH|LOCALE_ARCHIVE|NIX_PATH|NIXOS_INSTALL_BOOTLOADER|NIXOS_NO_CHECK)\\=[^ ]* )*";
  nhSteps = builtins.concatStringsSep "|" [
    # Set the system profile (the new generation).
    "nix build --no-link --profile /nix/var/nix/profiles/system ${system}"
    # Activate it.
    "${system}/bin/switch-to-configuration (switch|boot|test|dry-activate)"
  ];
in
{
  security.sudo.extraRules = [{
    groups = [ "wheel" ];
    commands = [
      { command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/env ^${envVars}(${nhSteps})$"; options = [ "NOPASSWD" ]; }
    ];
  }];
}
