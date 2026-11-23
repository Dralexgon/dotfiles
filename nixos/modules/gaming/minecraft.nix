{ pkgs, ... }:

let
  # Horizon (Minecraft Java rewritten in Rust): the prebuilt launcher from the GitHub releases,
  # run in an FHS environment like upstream's flake package (github:horizon-rust/horizon,
  # flake.nix), since it builds native mods itself with Cargo. Upstream's package compiles from
  # the ~900 MB repo; the release tarball is a 34 MB download. Self-update is off: Nix picks
  # the version. To update, bump `version` and set `hash` to lib.fakeHash, then rebuild and
  # copy the hash from the error (releases: gh release list -R horizon-rust/horizon).
  horizon-launcher-unwrapped = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "horizon-launcher-unwrapped";
    version = "0.2.107";
    src = pkgs.fetchzip {
      url = "https://github.com/horizon-rust/horizon/releases/download/launcher@${version}/horizon-launcher-linux-x86_64.tar.gz";
      hash = "sha256-UVUvq/CeC6sByQzyHZ1mKqlvQaf/dbzE0yUwVEUgDx8=";
      stripRoot = false;
    };
    installPhase = "install -Dm755 horizon-launcher $out/bin/horizon-launcher";
  };
  horizon-desktop = pkgs.makeDesktopItem {
    name = "horizon-launcher";
    desktopName = "Horizon";
    genericName = "Game launcher";
    comment = "Install, prepare and play Horizon, Minecraft: Java Edition rewritten in Rust";
    exec = "horizon-launcher";
    icon = "minecraft";
    categories = [ "Game" ];
    startupWMClass = "horizon-launcher";
  };
  horizon-launcher = pkgs.buildFHSEnv {
    pname = "horizon-launcher";
    inherit (horizon-launcher-unwrapped) version;
    targetPkgs = pkgs: with pkgs; [
      # Windowing, graphics, Vulkan, Wayland, X11
      vulkan-loader libglvnd wayland libxkbcommon
      libx11 libxcb libxcursor libxext libxi libxrandr libxrender libxxf86vm
      # Audio, udev
      udev udev.dev alsa-lib alsa-lib.dev
      # Desktop integration, fonts, keyring
      fontconfig freetype dbus xdg-utils procps
      # Mojang Java runtime dependencies
      zlib libxtst
      gamemode
      # Build environment for native mods (clang/mold/openssl from upstream's launcher/shell.nix)
      gcc glibc.dev pkg-config clang mold openssl openssl.dev
    ];
    runScript = "${horizon-launcher-unwrapped}/bin/horizon-launcher";
    profile = ''
      export HORIZON_LAUNCHER_NO_SELF_UPDATE=1
      export HORIZON_LAUNCHER_DESKTOP_EXEC="''${HORIZON_LAUNCHER_DESKTOP_EXEC:-horizon-launcher}"
      export PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/share/pkgconfig:''${PKG_CONFIG_PATH:-}"
      export LIBCLANG_PATH=${pkgs.llvmPackages.libclang.lib}/lib
    '';
    extraInstallCommands = ''
      install -Dm444 ${horizon-desktop}/share/applications/horizon-launcher.desktop -t $out/share/applications
    '';
  };
in
{
  hardware.graphics.enable = true;

  environment.systemPackages = with pkgs; [
    # Minecraft
    prismlauncher # Minecraft launcher
    # modrinth-app # Modrinth launcher
    # It crashes nixos-rebuild sometimes:
    # (pkgs.modrinth-app.overrideAttrs (oldAttrs: {
    #   buildCommand =
    #     ''
    #       gappsWrapperArgs+=(
    #          --set WEBKIT_DISABLE_DMABUF_RENDERER 1
    #          --set LIBGL_ALWAYS_SOFTWARE 1
    #          --set GDK_BACKEND x11
    #       )
    #     ''
    #     + oldAttrs.buildCommand;
    # }))
    zulu21 # Java for minecraft

    libglvnd # For minecraft forge

    # Horizon launcher with its native-mod build environment (see the let block)
    horizon-launcher
  ];

  # Minecraft server module
  # services.minecraft-servers = {
  #   enable = false;
  #   eula = true;
  #
  #   servers = {
  #     uwu = {
  #       enable = true;
  #       openFirewall = true;
  #     };
  #   };
  # };
}
