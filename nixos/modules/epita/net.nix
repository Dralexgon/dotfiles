{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    gns3-server
    gns3-gui
    docker
    dynamips
    ubridge
    inetutils
    # qemu # Really useful ?
    wireshark
    dig # for DNS queries
  ];

  users.users."alex".extraGroups = [
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
