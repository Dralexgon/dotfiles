{ pkgs, ... }:

{
  virtualisation.docker.enable = true;
  users.extraGroups.docker.members = [ "alex" ];
  users.users."alex".extraGroups = [
    "docker"
  ];
}
