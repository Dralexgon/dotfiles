{ config, pkgs, lib, inputs, ... }:

{
  swapDevices = [{
    device = "/swapfile";
    size = 16 * 1024; # 16GB
  }];
  zramSwap.enable = true; # Optimize swap
}
