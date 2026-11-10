{ username, ... }:

{
  virtualisation.docker.enable = true;
  users.users.${username}.extraGroups = [ "docker" ];
  # Maybe necessary
  # users.extraGroups.docker.members = [ username ];
}
