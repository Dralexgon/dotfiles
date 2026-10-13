{ config, pkgs, lib, inputs, ... }:

{
  swapDevices = [{
    device = "/swapfile";
    size = 16 * 1024; # 8GB
  }];
  zramSwap.enable = true; # Optimize swap
}
