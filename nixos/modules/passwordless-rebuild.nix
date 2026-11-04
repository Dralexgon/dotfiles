{ ... }:

# Lets admins (wheel) run `sudo nixos-rebuild` without a password, so tools
# like coding agents can rebuild on their own.
# WARNING: nixos-rebuild can build and switch to any config as root, so this
# is passwordless root for anything running as a wheel user.
{
  security.sudo.extraRules = [{
    groups = [ "wheel" ];
    commands = [{ command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }];
  }];
}
