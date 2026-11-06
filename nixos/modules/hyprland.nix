{ inputs, pkgs, ... }:

let
  # older way: nixpkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
  pkgs-stable = import inputs.nixpkgs-stable { system = pkgs.stdenv.hostPlatform.system; config.allowUnfree = true; };
  # use it as pkgs-stable.example

  # Colors from config/caelestia/schemes/vampire
  sddm-vampire = (pkgs.sddm-astronaut.override {
    themeConfig = {
      ScreenWidth = "3840";
      ScreenHeight = "2160";
      Font = "Cinzel";
      FontSize = "22"; # default (height / 80) is tiny at 4K
      RoundCorners = "12";
      HourFormat = "HH:mm";
      DateFormat = "dddd d MMMM";
      HeaderText = "";

      Background = "Backgrounds/vampire.jpg";
      CropBackground = "true";
      DimBackground = "0.35";
      DimBackgroundColor = "#0A0506";
      BackgroundColor = "#0A0506";

      HeaderTextColor = "#EFE3E4";
      DateTextColor = "#CDB6B9";
      TimeTextColor = "#EFE3E4";

      FormBackgroundColor = "#0A0506";
      LoginFieldBackgroundColor = "#1A0B0E";
      PasswordFieldBackgroundColor = "#1A0B0E";
      LoginFieldTextColor = "#EFE3E4";
      PasswordFieldTextColor = "#EFE3E4";
      UserIconColor = "#D3203C";
      PasswordIconColor = "#D3203C";
      PlaceholderTextColor = "#9C878A";
      WarningColor = "#FF4A5E";

      LoginButtonTextColor = "#FFF0F1";
      LoginButtonBackgroundColor = "#8A0012";
      SystemButtonsIconsColor = "#EFE3E4";
      SessionButtonTextColor = "#EFE3E4";
      VirtualKeyboardButtonTextColor = "#EFE3E4";

      DropdownTextColor = "#EFE3E4";
      DropdownSelectedBackgroundColor = "#2A0008";
      DropdownBackgroundColor = "#0D0607";

      HighlightTextColor = "#FFF0F1";
      HighlightBackgroundColor = "#D3203C";
      HighlightBorderColor = "#D3203C";

      HoverUserIconColor = "#FF4A5E";
      HoverPasswordIconColor = "#FF4A5E";
      HoverSystemButtonsIconsColor = "#FF4A5E";
      HoverSessionButtonTextColor = "#FF4A5E";
      HoverVirtualKeyboardButtonTextColor = "#FF4A5E";

      PartialBlur = "true";
      HaveFormBackground = "false";
      FormPosition = "center";
      HideVirtualKeyboard = "true";

      TranslatePlaceholderPassword = "Speak the word, mortal...";
      TranslateLoginFailedWarning = "The blood rejects you.";
    };
  }).overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      chmod u+w $out/share/sddm/themes/sddm-astronaut-theme/Backgrounds
      cp ${../../themes/sddm/vampire.jpg} $out/share/sddm/themes/sddm-astronaut-theme/Backgrounds/vampire.jpg
    '';
  });

  # Custom QML greeter: blood drips, Predatoria crest, bleeding password field, eyelids on login
  sddm-predatoria = pkgs.runCommand "sddm-predatoria-theme" { } ''
    mkdir -p $out/share/sddm/themes
    cp -r ${../../themes/sddm/predatoria} $out/share/sddm/themes/predatoria
    chmod u+w $out/share/sddm/themes/predatoria
    cp ${../../themes/sddm/vampire.jpg} $out/share/sddm/themes/predatoria/background.jpg
  '';
in
{
  # Vampire login screen: custom "predatoria" QML theme (themes/sddm/predatoria)
  # Previous try: sddm-astronaut recolored with the caelestia "vampire" scheme,
  # to get it back: theme = "sddm-astronaut-theme"; extraPackages = [ sddm-vampire ];
  services.displayManager.sddm = {
    enable = true;
    package = pkgs.kdePackages.sddm; # the theme is Qt6
    wayland.enable = true;
    # weston (the default) shows no mouse pointer on NVIDIA; kwin does
    wayland.compositor = "kwin";
    theme = "predatoria";
    settings.Theme = {
      CursorTheme = "Bibata-Modern-Classic"; # sweet-cursors (Hyprland's) isn't in nixpkgs
      CursorSize = 24; # kwin already scales it by the 4K output scale
    };
  };
  services.displayManager.defaultSession = "hyprland-uwsm";

  # Previous try: ly with a blood red DOOM fire (cool, but doesn't match the caelestia style)
  services.displayManager.ly = {
    enable = false;
    settings = {
      animation = "doom";
      doom_top_color = "0x00300000"; # flame tips (low intensity): dried blood
      doom_middle_color = "0x00A00000"; # crimson
      doom_bottom_color = "0x00FF2020"; # fire base (high intensity): bright blood
      doom_fire_height = 6; # 1 thru 9
      border_fg = "0x00B00000";
      fg = "0x00E8DCCB"; # bone white text
      bigclock = "en";
    };
  };
  # services.displayManager.gdm.enable = true;

  programs.hyprland = {
    enable = true;
    # package = pkgs-stable.hyprland; # to go to an old version of hyprland
    withUWSM = true; # to enable gtk portals
  };
  i18n.inputMethod.enable = false; # disable a notif

  # Screen sharing and gtk apps support
  xdg.portal.enable = true;
  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
  ];

  environment.systemPackages = with pkgs; [
    kitty # Hyprland console
    sddm-predatoria
    bibata-cursors # SDDM pointer
  ];

  fonts.packages = [ pkgs.cinzel ];
}
