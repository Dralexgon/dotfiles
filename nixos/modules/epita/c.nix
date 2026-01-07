{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    gcc # GNU C compiler
    gnumake # GNU make
    clang-tools # Clang format, clang-tidy, etc...

    criterion # Library to create testsuites for C programs

    # GNU autotools
    automake
    autoconf
    autoconf-archive
    libtool

    # GNU autotools v2
    automake
    autogen
    autoconf
    autoconf-archive
    libtool
    pkg-config
    m4
  ];

  environment.variables = {
    ACLOCAL_PATH = "${pkgs.autoconf-archive}/share/aclocal:${pkgs.autoconf}/share/aclocal:${pkgs.automake}/share/aclocal";
  };
}