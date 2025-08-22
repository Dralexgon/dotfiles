{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [
    #steam # Steam is already installed with the above option
    adwsteamgtk # GTK wrapper for Steam (gtk theme + better ui beacause steam is ugly)

    # osu-lazer

    # protonup
    # lutris
    # heroic
    # bottles

    # Unity launcher, to create games
    # unityhub
    # gameeky # Easy game maker ?
  ];
}
