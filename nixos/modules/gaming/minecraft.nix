{ pkgs, inputs, ... }:

let
  # Horizon (Minecraft Java rewritten in Rust): upstream's launcher package (flake input
  # `horizon`), in an FHS environment for native mods, with self-update off.
  horizon-launcher = inputs.horizon.packages.${pkgs.stdenv.hostPlatform.system}.horizon-launcher;
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

    # Horizon launcher (see the let block)
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
