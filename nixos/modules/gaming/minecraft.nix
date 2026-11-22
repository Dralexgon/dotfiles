{ pkgs, lib, ... }:

let
  # Horizon (Minecraft Java rewritten in Rust): the launcher builds the game itself when
  # native mods are installed, so it needs the libraries from upstream's launcher/shell.nix.
  # The launcher binary is not packaged: it lives in ~/Apps/horizon (from the GitHub releases).
  horizonLibs = with pkgs; [
    libxkbcommon wayland vulkan-loader fontconfig freetype alsa-lib openssl
    udev libx11 libxcb libxcursor libxrandr libxi
  ];
  horizon-launcher = pkgs.writeShellScriptBin "horizon-launcher" ''
    export PATH=${lib.makeBinPath (with pkgs; [ pkg-config clang mold stdenv.cc ])}:$PATH
    export PKG_CONFIG_PATH=${lib.makeSearchPathOutput "dev" "lib/pkgconfig" horizonLibs}:${lib.makeSearchPathOutput "dev" "share/pkgconfig" horizonLibs}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
    export LIBCLANG_PATH=${pkgs.llvmPackages.libclang.lib}/lib
    export LD_LIBRARY_PATH=${lib.makeLibraryPath horizonLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    exec ${pkgs.steam-run}/bin/steam-run "$HOME/Apps/horizon/horizon-launcher" "$@"
  '';
  horizon-desktop = pkgs.makeDesktopItem {
    name = "horizon-launcher";
    desktopName = "Horizon";
    comment = "Minecraft Java Edition rewritten in Rust";
    exec = "horizon-launcher";
    icon = "minecraft";
    categories = [ "Game" ];
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
    horizon-desktop
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
