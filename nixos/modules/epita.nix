{ pkgs, ... }:

{
  virtualisation.docker.enable = true;
  users.extraGroups.docker.members = [ "alex" ];
  users.users."alex".extraGroups = [ "docker" ];

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
    ninja

    # Man pages
    man-pages
    man-pages-posix

    # Afs
    krb5
    sshfs

    # GNU autotools
    automake
    autoconf
    autoconf-archive
    libtool

    # Javascript
    nodejs_20
    yarn

    # Mail
    thunderbird

    # Android
    android-studio

    # Net
    # gns3-server
    # gns3-gui
    # docker
    # dynamips
    # ubridge
    # inetutils

    # Java
    # nixpkgs-stable.jetbrains.idea-ultimate
    postgresql
    maven
  ];

  # Enable the GNS3 server
  # Give root permissions to ubridge (/!\ NOT TESTED)
  # security.wrappers = {
  #   ubridge = {
  #     source = "${pkgs.ubridge}/bin/ubridge";
  #     owner = "root";
  #     group = "root";
  #     permissions = "u+sx,g+sx,o+sx";
  #   };
  # };

}
