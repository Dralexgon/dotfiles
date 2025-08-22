{ pkgs, ... }:

{
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
  ];
}
