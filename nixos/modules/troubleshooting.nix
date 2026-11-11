{ pkgs, ... }:

# Troubleshooting tools + SSD / disk health monitoring.
# - smartd: periodic SMART checks, warnings in the journal + desktop popup.
#     journalctl -u smartd
# - scrutiny: web dashboard with temperature / wear history.
#     http://localhost:8080
# - CLI: sudo smartctl -a /dev/nvme0n1   |   sudo nvme smart-log /dev/nvme0n1
{
  environment.systemPackages = with pkgs; [
    smartmontools # smartctl
    nvme-cli # nvme smart-log
    memtest86plus
  ];

  services.smartd = {
    enable = true;
    autodetect = true;
    # -a: all checks, -n standby: don't wake sleeping disks,
    # -W 4,60,70: log temp changes >=4°C, info at 60°C, critical at 70°C,
    # -s: short self-test daily at 02:00, long self-test Saturdays at 03:00
    defaults.autodetected = "-a -o on -n standby,q -W 4,60,70 -s (S/../.././02|L/../../6/03)";
    notifications = {
      wall.enable = true;
      x11.enable = true;
    };
  };

  services.scrutiny = {
    enable = true;
    openFirewall = false; # local only
    settings.web.listen.port = 8080;
    collector = {
      enable = true;
      schedule = "*:0/15"; # collect SMART data every 15 min
    };
  };
}
