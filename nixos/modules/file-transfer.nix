{ ... }:

{
  networking.firewall.allowedTCPPorts = [ 22 8000 8384 ];

  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = true;
      AllowUsers = null; # Allows all users by default. Can be [ "user1" "user2" ]
      UseDns = true;
      X11Forwarding = false;
      PermitRootLogin = "prohibit-password"; # "yes", "without-password", "prohibit-password", "forced-commands-only", "no"
    };
  };

  # services.samba = {
  #   enable = true;
  #   openFirewall = true;  # allow LAN access
  #   settings = {
  #       "public" = {
  #       path = "/home/alex/Shared"; # folder to share
  #       browseable = true;
  #       "read only" = false;
  #       "guest ok" = true; # allow access without password
  #       # "create mask" = "0644";
  #       # "directory mask" = "0755";
  #       # "force user" = "username";
  #       # "force group" = "groupname";
  #     };
  #   };
  # };

  # services.samba-wsdd = {
  #   enable = true;
  #   openFirewall = true;
  # };

  # networking.firewall.enable = true;
  # networking.firewall.allowPing = true;
}