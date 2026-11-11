{ pkgs, ... }:

# File transfer from other devices. SSH (scp, sftp) itself is in ssh.nix.
{
  networking.firewall.allowedTCPPorts = [ 8000 8384 ];

  # Cloud sync / backups (OneDrive, Google Drive, ...)
  environment.systemPackages = with pkgs; [ rclone ];

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
