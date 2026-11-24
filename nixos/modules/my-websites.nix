{ config, lib, pkgs, username, ... }:

# My websites hub (~/dev/web/my-websites), shared with Tailscale Funnel:
#   https://<machine>.<tailnet>.ts.net (`tailscale funnel status` shows it).
# Edits to the folder show up on refresh, no rebuild needed.
#
# Who can do what is decided by the hub API (server/ports.py, runs as me on 127.0.0.1:7420)
# from the identity tailscaled adds to each request:
#   - tailnet visitors whose login is in ~/.config/my-websites/allowed-users (from
#     ~/dotfiles-private) see everything and can add / remove / start / stop sites;
#   - everyone else (the internet through Funnel, other tailnet users) gets a read-only hub
#     without the "private" sites, the run / stop / path fields and the unshared local ports.
# Logs: journalctl -u nginx -f / journalctl -u my-websites-ports -f
let
  hubPort = 8090; # local nginx port behind the Funnel (loopback only)
  funnelPort = 443; # the plain URL. Funnel only allows 443, 8443 (the wiki) and 10000.
  # Life Manager stays tailnet-only on 8447 (its run.sh).
  tailscale = config.services.tailscale.package;

  # To the API. nginx passes tailscaled's headers as-is: Tailscale-User-* / Tailscale-Funnel-Request
  # (who is looking) and X-Forwarded-Host (the public host:port, for the API's Origin check).
  toApi = path: { proxyPass = "http://127.0.0.1:7420${path}"; };
in
{
  services.nginx = {
    enable = true;

    virtualHosts."my-websites" = {
      listen = [ { addr = "127.0.0.1"; port = hubPort; } ];
      root = "/var/www/my-websites";
      locations."/api/" = toApi "";
      # The raw sites.js has the private sites and the run commands: the API filters it per visitor
      locations."= /sites.js" = toApi "/api/sites.js";
      locations."/server/".return = "404";
      locations."~ /\\.".return = "404"; # .git, .gitignore, the API's temp files
      extraConfig = ''
        # Files change often: always revalidate
        add_header Cache-Control "no-cache";
      '';
    };
  };

  # nginx can't enter my home (chmod 700), so mount the site folder (read-only) where it can read it.
  systemd.services.nginx.serviceConfig.BindReadOnlyPaths = [
    # "-" = skip if the folder is missing, instead of failing nginx.
    "-/home/${username}/dev/web/my-websites:/var/www/my-websites"
  ];

  # Puts the hub on the internet (and the tailnet) at the machine's plain URL.
  systemd.services.my-websites-funnel = lib.mkIf config.services.tailscale.enable {
    description = "Tailscale Funnel for the websites hub";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # tailscaled may not be logged in yet right after boot: retry
      Restart = "on-failure";
      RestartSec = 15;
      ExecStart = "${tailscale}/bin/tailscale funnel --bg --yes --https=${toString funnelPort} http://127.0.0.1:${toString hubPort}";
      ExecStop = "${tailscale}/bin/tailscale funnel --https=${toString funnelPort} off";
    };
  };

  systemd.services.my-websites-ports = {
    description = "API for the websites hub";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 ] ++ lib.optional config.services.tailscale.enable tailscale;
    # Skip (not fail) when the project isn't there, so rebuilds don't error out.
    unitConfig.ConditionPathExists = "/home/${username}/dev/web/my-websites/server/ports.py";
    serviceConfig = {
      User = username;
      ExecStart = "${pkgs.python3}/bin/python3 /home/${username}/dev/web/my-websites/server/ports.py";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
