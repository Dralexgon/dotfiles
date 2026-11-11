{ ... }:

# Tailscale: private network (tailnet) to share local services (e.g. the Wholmund wiki) with friends.
# First time: `sudo tailscale up` to log in. Share the machine from https://login.tailscale.com/admin/machines
{
  services.tailscale.enable = true; # also installs the `tailscale` CLI

  networking.firewall = {
    # Only open what is needed, and only to tailnet devices (not the public internet)
    interfaces."tailscale0".allowedTCPPorts = [ 3001 ]; # Wholmund wiki (Next.js)
    allowedUDPPorts = [ 41641 ]; # direct (peer-to-peer) connections instead of relays
  };
}
