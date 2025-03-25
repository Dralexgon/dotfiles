{ config, pkgs, lib, inputs, ... }:

{
  swapDevices = [{
    device = "/swapfile";
    size = 4 * 1024; # 4GB
  }];
}
