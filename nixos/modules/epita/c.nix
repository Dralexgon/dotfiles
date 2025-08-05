{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    gcc
    gnumake
    clang-tools

    # # GNU autotools
    # automake
    # autoconf
    # autoconf-archive
    # libtool
  ];
}