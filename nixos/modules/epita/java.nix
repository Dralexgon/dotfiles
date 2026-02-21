{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    jetbrains.idea-ultimate
    postgresql
    maven

    podman
  ];
}
