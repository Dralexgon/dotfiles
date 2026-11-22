{ pkgs, inputs, ... }:

let
  # Packages that aren't in nixpkgs, named so that they are plain lines of
  # environment.systemPackages (and can be toggled with nixcfg). A let name
  # wins over `with pkgs;`.
  zen-browser = inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default;
  # Saves/restores the Zen sidebar to config/zen/sidebar.json (tools/zen-sidebar)
  zen-sidebar = import ../../tools/zen-sidebar { inherit pkgs; };
in
{
  environment.systemPackages = with pkgs; [
    # Web browsers
    firefox # Always useful to have at least one
    zen-browser # Smooth browser, the best one !
    zen-sidebar # Sync the Zen sidebar with dotfiles (config/zen/sidebar.json)
    # tor-browser
    # brave
    # chromium
  ];
}

