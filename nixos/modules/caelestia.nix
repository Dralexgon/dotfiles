{ inputs, pkgs, ... }:

let
  # Mouse pointer trail, drawn by Hyprland itself (tools/hypr-cursortrail).
  # Built against pkgs.hyprland: it refuses to load into another Hyprland version.
  cursortrail = import ../../tools/hypr-cursortrail { inherit pkgs; };
  # Workspace overview (SUPER + Tab), hyprexpo ported to the current Hyprland (tools/hypr-expo).
  hyprexpo = import ../../tools/hypr-expo { inherit pkgs; };
  # Liquid Glass / Acrylic / Mica window effects (flake input hyprliquid, tools/hypr-liquid).
  hyprliquid = import ../../tools/hypr-liquid { inherit pkgs; src = inputs.hyprliquid; };
  # Closing windows shatter into petals blown by the wind (tools/hypr-petals).
  petals = import ../../tools/hypr-petals { inherit pkgs; };
  # Preferred overview, but it often lags behind Hyprland. A failed build leaves lib/ empty instead of
  # failing the system build, and hypr-user.lua then falls back to hyprexpo. It is retried whenever
  # nixpkgs updates it (or Hyprland).
  hyprtasking = pkgs.hyprlandPlugins.hyprtasking.overrideAttrs {
    buildPhase = ''
      runHook preBuild
      ninja -j$NIX_BUILD_CORES || echo "hyprtasking does not build against this Hyprland, hyprexpo will be used instead"
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib
      if [ -f libhyprtasking.so ]; then ninja install; fi
      runHook postInstall
    '';
  };
in
{
  # Stable path for hl.plugin.load in config/caelestia/hypr-user.lua
  environment.etc."hypr/plugins/cursortrail.so".source = "${cursortrail}/lib/libcursortrail.so";
  environment.etc."hypr/plugins/hyprexpo.so".source = "${hyprexpo}/lib/libhyprexpo.so";
  environment.etc."hypr/plugins/hyprliquid.so".source = "${hyprliquid}/lib/libhyprliquid.so";
  environment.etc."hypr/plugins/petals.so".source = "${petals}/lib/libpetals.so";
  # A directory: libhyprtasking.so is only there when hyprtasking built
  environment.etc."hypr/plugins/hyprtasking".source = "${hyprtasking}/lib";

  environment.systemPackages = with pkgs; [
    inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.caelestia-cli.packages.${pkgs.stdenv.hostPlatform.system}.default

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

    # Recolours Yaru folders to the exact scheme primary, called by apply-scheme.sh
    (writers.writePython3Bin "caelestia-recolor-folders" {
      libraries = with python3Packages; [ pillow numpy ];
      flakeIgnore = [ "E203" "E501" "W503" ];
    } (builtins.readFile ../../config/caelestia/recolor-folders.py))
  ];

  # Adds the system profile to QT_PLUGIN_PATH so Qt apps (quickshell) can load qtengine.
  # platformTheme is left unset: QT_QPA_PLATFORMTHEME=qtengine comes from the Hyprland env.
  qt.enable = true;
}