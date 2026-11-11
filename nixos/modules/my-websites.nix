{ lib, pkgs, username, ... }:

# Serves my websites hub (~/dev/web/my-websites) on http://localhost.
# Only reachable from this PC. Edits to the folder show up on refresh, no rebuild needed.
# /api/ports lists the local ports that answer HTTP (server/ports.py, runs as me on 127.0.0.1:7420).
# Logs: journalctl -u nginx -f / journalctl -u my-websites-ports -f
let
  # Short names for my local sites: http://<name>.localhost -> localhost:<port>.
  # Browsers and Linux send every *.localhost name to this PC, so no DNS setup is needed.
  # The hub reads this list (/domains.json) to link to the short names.
  domains = {
    life-manager = 5173;
    wholmund = 3001;
    webui = 3000;
    flask = 5000;
  };

  localOnly = [
    { addr = "127.0.0.1"; port = 80; }
    { addr = "[::1]"; port = 80; }
  ];

  domainsJson = pkgs.writeText "domains.json" (builtins.toJSON domains);
in
{
  services.nginx = {
    enable = true;

    virtualHosts = {
      "localhost" = {
        default = true;
        listen = localOnly;
        root = "/var/www/my-websites";
        locations."/api/".proxyPass = "http://127.0.0.1:7420";
        locations."= /domains.json".alias = domainsJson;
        extraConfig = ''
          # Files change often: always revalidate
          add_header Cache-Control "no-cache";
        '';
      };
    } // lib.mapAttrs' (name: port: lib.nameValuePair "${name}.localhost" {
      listen = localOnly;
      locations."/" = {
        proxyPass = "http://localhost:${toString port}"; # tries 127.0.0.1 and ::1 (Vite only listens on ::1)
        proxyWebsockets = true; # live reload (Vite, Next.js)
        recommendedProxySettings = true; # keeps the Host header, so the app sees <name>.localhost
      };
    }) domains;
  };

  # nginx can't enter my home (chmod 700), so mount the site folder (read-only) where it can read it.
  systemd.services.nginx.serviceConfig.BindReadOnlyPaths = [
    "/home/${username}/dev/web/my-websites:/var/www/my-websites"
  ];

  systemd.services.my-websites-ports = {
    description = "Ports API for the websites hub";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      User = username;
      ExecStart = "${pkgs.python3}/bin/python3 /home/${username}/dev/web/my-websites/server/ports.py";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
