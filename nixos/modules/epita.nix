{ pkgs, ... }:

{
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
    typescript

    # Mail
    thunderbird

    # Android
    android-studio

    # Net
    gns3-server
    gns3-gui
    docker
    dynamips
    ubridge
    inetutils
    qemu
    dig # for DNS queries

    # Java
    # nixpkgs-stable.jetbrains.idea-ultimate
    postgresql
    maven
  ];

  virtualisation.docker.enable = true;
  users.extraGroups.docker.members = [ "alex" ];
  users.users."alex".extraGroups = [
    "docker"
    "ubridge"
  ];

  # Edit the file : ~/.config/GNS3/2.2/gns3_server.conf
  # with : ubridge_path = /run/wrappers/bin/ubridge
  users.groups.ubridge = { };
  security.wrappers.ubridge = {
    source = "/run/current-system/sw/bin/ubridge";
    capabilities = "cap_net_admin,cap_net_raw=ep";
    owner = "root";
    group = "ubridge";
    permissions = "u+rx,g+x";
  };

}
