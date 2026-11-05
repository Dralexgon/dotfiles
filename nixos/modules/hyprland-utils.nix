{ inputs, pkgs, ... }:

let
  pkgs-stable = import inputs.nixpkgs-stable { system = pkgs.stdenv.hostPlatform.system; config.allowUnfree = true; };
in
{
  environment.systemPackages = with pkgs; [
    rofi # App launcher
    waybar # Status bar at the top of the screen
    kitty # Hyprland console
    hyprlock # Lock screen
    hyprpaper # Wallpaper manager
    yazi # File explorer (terminal)
    nautilus # File explorer (GUI)
    awww # Another wallpaper manager
    swaynotificationcenter # Notification menu (is dunst better ?)
    clipse # Clipboard manager
    wl-clipboard # Another clipboard manager
    wlogout # Logout menu
    pavucontrol # Sound GUI
    # networkmanagerapplet # Wifi menu: nm-applet --indicator
    grim # Screenshot
    slurp # Screenshot area selector
    hyprshot # Screenshot

    # Ricing
    python3
    pkgs-stable.pywal # unstable pywal16 fails to build (makeWrapper --prefix bug)

    #ZaneyOS conf
    eza
    bat
    starship
    fzf # FuzzyFinder, used to search file. I should use it more
  ];
}
