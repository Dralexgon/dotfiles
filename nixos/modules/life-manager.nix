{ ... }:

# Starts my life-manager website (~/dev/apps/life-manager) at boot, in prod mode
# on http://localhost:7420. Logs: journalctl -u life-manager -f
{
  systemd.services.life-manager = {
    description = "life-manager website";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    # The assistant runs claude, git and Bash as me, so give it my system tools.
    environment.PATH = "/run/wrappers/bin:/run/current-system/sw/bin";

    serviceConfig = {
      User = "alex";
      WorkingDirectory = "/home/alex/dev/apps/life-manager";
      ExecStart = "/home/alex/dev/apps/life-manager/run.sh prod";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
