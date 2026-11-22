{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    jetbrains.idea # previous: jetbrains.idea-ultimate
    postgresql
    maven

    podman
  ];
}
