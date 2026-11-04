{ inputs, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    inputs.caelestia-shell.packages.${system}.default
    inputs.caelestia-cli.packages.${system}.default

    # Not sure if all these dependencies are necessary or not
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    hyprpicker
    hypridle
    wl-clipboard
    cliphist
    bluez
    bluez-tools
    inotify-tools
    app2unit
    wireplumber
    trash-cli
    foot
    fish
    fishPlugins.bass
    fastfetch
    starship
    btop
    jq
    socat
    imagemagick
    curl
    adw-gtk3
    papirus-icon-theme
    kdePackages.qt6ct
    libsForQt5.qt5ct
    qtengine # Qt platform theme set by the caelestia Hyprland env (QT_QPA_PLATFORMTHEME=qtengine)
    darkly # Qt style used by ~/.config/qtengine/config.json
    nerd-fonts.jetbrains-mono
    gpu-screen-recorder
    spicetify-cli
  ];

  # Adds the system profile to QT_PLUGIN_PATH so Qt apps (quickshell) can load qtengine.
  # platformTheme is left unset: QT_QPA_PLATFORMTHEME=qtengine comes from the Hyprland env.
  qt.enable = true;
}