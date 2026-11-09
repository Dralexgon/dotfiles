{ inputs, pkgs, ... }:

let
  # Mouse pointer trail, drawn by Hyprland itself (tools/hypr-cursortrail).
  # Built against pkgs.hyprland: it refuses to load into another Hyprland version.
  cursortrail = import ../../tools/hypr-cursortrail { inherit pkgs; };
  # Workspace overview (SUPER + Tab), hyprexpo ported to the current Hyprland (tools/hypr-expo).
  hyprexpo = import ../../tools/hypr-expo { inherit pkgs; };
  # Liquid Glass / Acrylic / Mica window effects (flake input hyprliquid, tools/hypr-liquid).
  hyprliquid = import ../../tools/hypr-liquid { inherit pkgs; src = inputs.hyprliquid; };
  # Closing / opening window animations: petals blown by the wind or blood (tools/hypr-windowfx).
  windowfx = import ../../tools/hypr-windowfx { inherit pkgs; };
  # Petals, blood drops or images thrown behind the mouse pointer (tools/hypr-cursorfx).
  cursorfx = import ../../tools/hypr-cursorfx { inherit pkgs; };
  # Preferred overview, but it often lags behind Hyprland. A failed build leaves lib/ empty instead of
  # failing the system build, and hypr-user.lua then falls back to hyprexpo. It is retried whenever
  # nixpkgs updates it (or Hyprland).
  # caelestia-cli only reads schemes from its own data dir, so our schemes (config/caelestia/schemes) are
  # copied into it. The package has its own patchPhase, which skips postPatch, hence appending to it.
  caelestia-cli = inputs.caelestia-cli.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    patchPhase = (old.patchPhase or "") + ''
      cp -r ${../../config/caelestia/schemes}/. src/caelestia/data/schemes/
    '';
  });
  # Petals lock screen (config/caelestia/lock), only active with the petals scheme: falling petals pushed
  # by the mouse, a flower blooming behind the profile picture as you type (wilting on a wrong
  # password), blossom password dots, and a petal burst on unlock. The new QML files are copied in,
  # lock-petals.patch hooks them into Caelestia's lock. If upstream changes these files the patch
  # fails and so does the build, rather than shipping a broken lock screen.
  caelestia-shell = inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../../config/caelestia/lock/lock-petals.patch ];
    postPatch = (old.postPatch or "") + ''
      cp ${../../config/caelestia/lock/PetalShape.qml} modules/lock/PetalShape.qml
      cp ${../../config/caelestia/lock/PetalField.qml} modules/lock/PetalField.qml
      cp ${../../config/caelestia/lock/PetalBloom.qml} modules/lock/center/PetalBloom.qml
    '';
  });
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
  environment.etc."hypr/plugins/windowfx.so".source = "${windowfx}/lib/libwindowfx.so";
  environment.etc."hypr/plugins/cursorfx.so".source = "${cursorfx}/lib/libcursorfx.so";
  # A directory: libhyprtasking.so is only there when hyprtasking built
  environment.etc."hypr/plugins/hyprtasking".source = "${hyprtasking}/lib";

  environment.systemPackages = with pkgs; [
    caelestia-shell
    caelestia-cli

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