{ pkgs, ... }:

let
  # Packages that aren't in nixpkgs, named so that they are plain lines of
  # environment.systemPackages (and can be toggled with nixcfg). A let name
  # wins over `with pkgs;`.
  zen-browser = inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
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