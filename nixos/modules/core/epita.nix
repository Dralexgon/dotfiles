{ config, pkgs, lib, inputs, ... }:

{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # C
    gcc
    gnumake
    clang-tools

    # C++
    gcc
    gnumake
    clang-tools
    cmake

    # Afs
    krb5
    sshfs

    # GNU autotools
    automake
    autoconf
    autoconf-archive
    libtool

    # Net
    # gns3-server
    # gns3-gui
    # docker
    # dynamips
    # ubridge
    # inetutils

    # Java
    # nixpkgs-stable.jetbrains.idea-ultimate
    # postgresql
    # maven
  ];

}
