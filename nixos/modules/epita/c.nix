{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    gcc # GNU C compiler
    gnumake # GNU make
    clang-tools # Clang format, clang-tidy, etc...

    criterion # Library to create testsuites for C programs

    # # GNU autotools
    # automake
    # autoconf
    # autoconf-archive
    # libtool
  ];
}