# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, inputs, ... }:

let
  conf_hyprland = true;
  conf_gnome = true;
  conf_epita = true;
  conf_razer = true;
  nixpkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
in

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      inputs.nix-minecraft.nixosModules.minecraft-servers
    ];
  nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];

  # Added by flake boot-animation
  # nixos-boot = {
  #   enable = true;
  #   theme = "evil-nixos";
  # };

  # Bootloader.
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    useOSProber = true;
    theme = pkgs.catppuccin-grub;
  };
  boot.plymouth.enable = true;
  boot.plymouth.themePackages = [ pkgs.catppuccin-plymouth ];
  # boot.plymouth.theme = "catppuccin";
  # boot.loader.systemd-boot.enable = true;

  # fileSystems."/mnt/ubuntu" = {
  #   device = "/dev/nvme0n1p4";
  #   options = ["nofail"];
  # };

  # swapDevices = [{
  #   device = "/swapfile";
  #   size = 8 * 1024; # 16GB
  # }];


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

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Configure console keymap
  console.keyMap = "us";

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
  boot.blacklistedKernelModules = [ "wlp10s0" ]; # "rtw88_8821ce" "rtl8822ce" ];
  # boot.kernelParams = [ "modprobe.blacklist=rtw88_8821ce" ]; #    rtl8821ce-dkms

  # Todo: try that
  # boot.extraModprobeConfig = "blacklist wlp10s0";

  hardware.graphics = { # for minecraft forge
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };


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


  # services.flatpak.enable = true;
  # flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo


  programs.ssh.startAgent = true;
  virtualisation.docker.enable = conf_epita;
  users.extraGroups.docker.members = [ "alex" ];


  fonts.packages = with pkgs; [
    # nerdfonts
    # Nerd fonts for Neovim
    jetbrains-mono
    # font-awesome
    # nerd-fonts.jetbrains-mono
    # nerd-fonts.symbols-only
    # nerd-fonts.font-awesome
    # Not sure if the following fonts are needed
    # noto-fonts-emoji
    # noto-fonts-cjk-sans
    # symbola
    # material-icons
  ];

  # fonts.fontDir.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # Web browsers
    firefox

    # Text editors/IDE
    vim
    vscode
    (pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.clion ["github-copilot"])
    (pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.idea-ultimate ["github-copilot"])

    warp-terminal

    # Neovim packages
    neovim
    lua
    cargo
    # jetbrains-mono
    # font-awesome
    luarocks
    lazygit
    fd
    ripgrep
    nodejs # For copilot nvim

    # Simple useful tools
    git
    wget
    unzip
    tree
    fragments # Bit toorent client
    gcolor3 # Color picker
    amberol
    xorg.xkill

    # Simple useful tools for Nixos
    nix-output-monitor
    nvd
    nh

    # 2 discord clients for multiple accounts
    discord
    vesktop

    # General ricing
    fastfetch # Most important ricing tool (that's the nice logo in the terminal)
    btop # System monitor
    dconf-editor
    nwg-look
    home-manager
    python3
    pywal
    dconf-editor
    nwg-look
    home-manager
    polychromatic # Razer GUI
    
    eww # This can be used to create a custom bar. I will try to do my own menu with it

    # Ricing visual
    fastfetch
    cmatrix
    cbonsai
    pipes-rs

    # catppuccin rice
    catppuccin-cursors.macchiatoMauve
    catppuccin-gtk

    # To draw art
    # python312Full
    # python3Packages.tkinter

    # Games
    unityhub # Unity launcher

    # Minecraft
    prismlauncher # Minecraft launcher
    # modrinth-app # Modrinth launcher
    (pkgs.modrinth-app.overrideAttrs (oldAttrs: {
      buildCommand =
        ''
          gappsWrapperArgs+=(
             --set WEBKIT_DISABLE_DMABUF_RENDERER 1
          )
        ''
        + oldAttrs.buildCommand;
    }))
    # zulu17
    zulu21

    libglvnd # For minecraft forge
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
    grim # Screenshot
    slurp # Screenshot area selector
    hyprshot # Screenshot

    # Ricing
    python3
    pywal

    #ZaneyOS conf
    eza
    bat
    starship
    fzf # FuzzyFinder, used to search file. I should use it more
  ] else []
  ) ++ (
  if conf_epita then
  [
    # C
    gcc
    gnumake
    clang-tools

    # C++
    gcc
    gnumake
    clang-tools
    cmake

    # Afs
    krb5
    sshfs

    # GNU autotools
    automake
    autoconf
    autoconf-archive
    libtool

    # Net
    # gns3-server
    # gns3-gui
    # docker
    # dynamips
    # ubridge
    # inetutils

    # Java
    # nixpkgs-stable.jetbrains.idea-ultimate
    postgresql
    maven
  ] else []
  ) ++ (
  if conf_gnome then
  [
    tilix

    gnome-tweaks
    gnome-extension-manager
    gnomeExtensions.user-themes
    gnomeExtensions.blur-my-shell
    gnomeExtensions.custom-accent-colors
    gnomeExtensions.dash2dock-lite
    gnomeExtensions.compiz-windows-effect
    gnomeExtensions.compiz-alike-magic-lamp-effect
    # Better gnome terminal and can use themes but
    # must be installed with flatpak for full features.
    # Unfortunately, NixOS and other package managers... You know
    blackbox-terminal
    # gnome-software
    # flatpak

    # Gnome music contribution
    gnome-builder
    meson
    pkg-config
    libadwaita
    gtk4
    flatpak-builder
    # apostrophe # Markdown editor
    # element-desktop

    #nix-software-center

    #gnome-shell-extension-dash-to-dock
    #gnome-shell-extension-appindicator
    #gnome-shell-extension-user-theme
    
    # Gnome ricing
    catppuccin-gtk
    gnomeExtensions.user-themes
    catppuccin-cursors.macchiatoMauve
    gnomeExtensions.custom-accent-colors
  ] else []
  )
  ;

  services.flatpak.enable = true;

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
  # security.wrappers = {
  #   ubridge = {
  #     source = "${pkgs.ubridge}/bin/ubridge";
  #     owner = "root";
  #     group = "root";
  #     permissions = "u+sx,g+sx,o+sx";
  #   };
  # };

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
  hardware.openrazer.users = ["alex"];





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
