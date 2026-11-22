{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    unityhub
    # gameeky # Easy game maker ?
  ];
}
