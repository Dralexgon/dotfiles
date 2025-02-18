# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, inputs, ... }:

let
  conf_hyprland = true;
  conf_gnome = true;
  conf_epita = true;
in

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      inputs.nix-minecraft.nixosModules.minecraft-servers
    ];
  nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # boot.loader.grub.enable = true;
  # boot.loader.grub.device = "nodev";
  # boot.loader.grub.useOSProber = true;

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Paris";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };
  # i18n.defaultLocale = "en_US.UTF-8";
  # i18n.extraLocaleSettings = {
  #   LC_ADDRESS = "en_EN.UTF-8";
  #   LC_IDENTIFICATION = "en_EN.UTF-8";
  #   LC_MEASUREMENT = "en_EN.UTF-8";
  #   LC_MONETARY = "en_EN.UTF-8";
  #   LC_NAME = "en_EN.UTF-8";
  #   LC_NUMERIC = "en_EN.UTF-8";
  #   LC_PAPER = "en_EN.UTF-8";
  #   LC_TELEPHONE = "en_EN.UTF-8";
  #   LC_TIME = "en_EN.UTF-8";
  #   #LC_ALL="C";
  # };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Configure console keymap
  console.keyMap = "fr";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false; # old versions
  # services.pulseaudio.enable = false; # new versions
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };






  networking.hostName = "nixos"; # Define your hostname.

  system.autoUpgrade.enable = true;# Enable the automatic upgrade, disabled by default.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Trying to fix wifi card driver
  # boot.kernelParams = [ "modprobe.blacklist=rtw88_8821ce" ]; #    rtl8821ce-dkms

  # hardware.opengl.enable = true; # for minecraft forge

  # programs.hyprland.enable = conf == 1;
  # services.xserver.desktopManager.gnome.enable = conf == 2;
  services.xserver.displayManager = {
    gdm.enable = conf_gnome;
    #gdm.enableGnomeKeyring = conf_gnome;
  };
  services.xserver.desktopManager.gnome.enable = conf_gnome;
  programs.hyprland.enable = conf_hyprland;

  # Enable the X11 windowing system.
  services.xserver = {
    enable = conf_gnome;
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  # Screensharing in hyrpland (not tested)
  xdg.portal.enable = conf_hyprland;
  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-gtk
    pkgs.xdg-desktop-portal-hyprland
  ];

  programs.ssh.startAgent = true;
  # virtualisation.docker.enable = conf_epita;
  #users.extraGroups.docker.members = [ "alex" ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # Web browsers
    firefox

    # Text editors/IDE
    vim
    vscode

    # Neovim packages
    neovim
    lua
    luarocks
    lazygit
    nodejs # For copilot nvim

    # Nerd fonts for Neovim
    jetbrains-mono
    font-awesome
    # Not sure if the following fonts are needed
    noto-fonts-emoji
    noto-fonts-cjk-sans
    symbola
    material-icons

    # Simple useful tools
    git
    github-desktop
    wget
    tree
    fragments # Bit toorent client
    gcolor3 # Color picker

    # 2 discord clients for multiple accounts
    discord
    vesktop

    # Ricing
    btop
    fastfetch
    catppuccin-gtk
    python3
    pywal
    dconf-editor
    nwg-look
    home-manager
    gnomeExtensions.user-themes
    catppuccin-cursors.macchiatoMauve
    gnomeExtensions.custom-accent-colors

    # To draw art
    # python312Full
    # python3Packages.tkinter

    # Games
    prismlauncher # Minecraft launcher
    unityhub # Unity launcher
  ] ++ (
  if conf_hyprland then
  [
    rofi-wayland # App launcher
    waybar # Status bar at the top of the screen
    kitty # Hyprland console
    hyprlock # Lock screen
    hyprpaper # Wallpaper manager
    swww # Another wallpaper manager
    swaynotificationcenter # Notification menu (is dunst better ?)
    clipse # Clipboard manager
    wl-clipboard # Another clipboard manager
    wlogout # Logout menu
    pavucontrol # Sound GUI
    networkmanagerapplet # Wifi menu: nm-applet --indicator

    # Not tested
    grim # Screenshot
    slurp # Screenshot area selector
    hyprshot # Screenshot

    #ZaneyOS conf
    eza
    bat
    starship
    fzf # FuzzyFinder, used to search file. I should use it more
  ] else []
  ) ++ (
  if conf_epita then
  [
    # C language
    gcc
    gnumake

    # Afs
    # krb5
    # sshfs

    # GNU autotools
    # automake
    # autoconf
    # autoconf-archive
    # libtool

    # Net
    # gns3-server
    # gns3-gui
    # docker
    # dynamips
    # ubridge
    # inetutils

    # Java
    # jetbrains.idea-ultimate
    # postgresql
    # maven
  ] else []
  ) ++ (
  if conf_gnome then
  [
    gnome-tweaks

    # Gnome music contribution
    gnome-builder
    meson
    pkg-config
    # typora
    # element-desktop

    #nix-software-center

    #gnome-shell-extension-dash-to-dock
    #gnome-shell-extension-appindicator
    #gnome-shell-extension-user-theme
  ] else []
  )
  ;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.alex = {
    isNormalUser = true;
    description = "alex";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [
      #thunderbird
    ];
  };

  # Give root permissions to ubridge (/!\ NOT TESTED)
  security.wrappers = {
    ubridge = {
      source = "${pkgs.ubridge}/bin/ubridge";
      owner = "root";
      group = "root";
      permissions = "u+sx,g+sx,o+sx";
    };
  };

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

  hardware.openrazer.enable = true;





  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable experimental features like flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
