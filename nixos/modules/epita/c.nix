{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    gcc # GNU C compiler
    gnumake # GNU make
    clang-tools # Clang format, clang-tidy, etc...
    # criterion (testsuites for C programs) is in criterion.nix

    # GNU autotools
    automake
    autogen
    autoconf
    autoconf-archive
    libtool
    pkg-config
    m4

    valgrind # Debugging
  ];

  environment.variables = {
    ACLOCAL_PATH = "${pkgs.autoconf-archive}/share/aclocal:${pkgs.autoconf}/share/aclocal:${pkgs.automake}/share/aclocal";
  };
}