{ username, ... }:

# Starts my life-manager website (~/dev/apps/life-manager) at boot, in dev mode (live reload)
# on http://localhost:5173. Logs: journalctl -u life-manager -f
{
  systemd.services.life-manager = {
    description = "life-manager website";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    # The assistant runs claude, git and Bash as me, so give it my system tools.
    path = [ "/run/wrappers" "/run/current-system/sw" ];

    serviceConfig = {
      User = username;
      WorkingDirectory = "/home/${username}/dev/apps/life-manager";
      ExecStart = "/home/${username}/dev/apps/life-manager/run.sh dev";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
