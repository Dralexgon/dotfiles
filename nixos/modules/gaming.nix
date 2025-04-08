{ config, pkgs, lib, inputs, ... }:

{
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [
    #steam # Steam is already installed with the above option
    adwsteamgtk # GTK wrapper for Steam (gtk theme + better ui beacause steam is ugly)

    protonup
    lutris
    heroic
    bottles

    # Unity launcher, to create games
    unityhub 

    # Minecraft
    prismlauncher # Minecraft launcher
    # modrinth-app # Modrinth launcher
    # It crashes nixos-rebuild sometimes:
    # (pkgs.modrinth-app.overrideAttrs (oldAttrs: {
    #   buildCommand =
    #     ''
    #       gappsWrapperArgs+=(
    #          --set WEBKIT_DISABLE_DMABUF_RENDERER 1
    #       )
    #     ''
    #     + oldAttrs.buildCommand;
    # }))
    zulu21 # Java for minecraft

    libglvnd # For minecraft forge
  ];
}
