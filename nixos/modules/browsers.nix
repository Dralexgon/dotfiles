{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Web browsers
    firefox # Always useful to have at least one
    zen-browser # Smooth browser, the best one !
    # tor-browser
    # brave
    # chromium
  ];
}