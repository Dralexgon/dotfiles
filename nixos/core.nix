# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, inputs, ... }:

let
  # older way: nixpkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
  pkgs-stable = import inputs.nixpkgs-stable { system = pkgs.system; config.allowUnfree = true; };
  # use it as pkgs-stable.example
in

{
  imports = [
    #inputs.nix-minecraft.nixosModules.minecraft-servers
  ];
  #nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];

  # Added by flake boot-animation
  # nixos-boot = {
  #   enable = true;
  #   theme = "evil-nixos";
  # };

  # Bootloader.
  boot.loader = {
    efi.canTouchEfiVariables = true;
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      useOSProber = true;
      theme = pkgs.catppuccin-grub;
    };
  };
  # boot.loader.systemd-boot.enable = true; # Default boot loader

  # Sync clock with windows dual boot
  time.hardwareClockInLocalTime = true;



  ##############################
  # Configure your system here #
  ##############################

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
  };


  # programs.ssh.startAgent = true;

  fonts.packages = with pkgs; [
    jetbrains-mono
  ];

  # fonts.fontDir.enable = true;

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # Libraries expected to be in /usr/lib
      # curl.dev
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # Web browsers
    firefox
    # tor-browser
    # brave
    # chromium

    # Text editors/IDE
    vim
    vscode
    # or activate modules/jetbrains.nix in configuration.nix
    
    # Terminal <3 meow
    kitty # In kitty.conf set linux_display_server to x11 to have the same look as gnome-terminal
    # Set font to JetBrains Mono Nerd Font Mono if you want to use nerd fonts

    # Simple useful tools
    git
    tree
    tldr # better man (man pages)
    wget
    unzip
    xorg.xkill

    # Simple useful apps
    libreoffice # Office suite
    drawing # Paint
    clapper # Video player
    eyedropper # Color picker
    amberol # Music player
    eartag # Music tag editor
    papers # PDF viewer
    inspector # "About your computer" app
    fragments # Bit torrent client
    gnome-frog # Extract text from images
    turnon # Turn on remote computers

    # Simple useful tools for Nixos
    nh # Beautiful rebuild switch animation (nh os rebuild)
    nix-output-monitor # Same but work with more things
    nvd # View package difference between generations
    # Example:
    # - nvd history
    # nvd diff /nix/var/nix/profiles/system-{42,43}-link
    nil # Nix lsp (language server protocol) for errors and warnings in .nix files

    # 2 discord clients for multiple accounts
    discord
    vesktop
  ];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.alex = {
    isNormalUser = true;
    description = "alex";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [
      #thunderbird
    ];
  };

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







  #########################################
  # Mandatory options that I never change #
  #########################################

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

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Allow unfree packages v2 (not sure if it works)
  environment.variables = {
    NIXPKGS_ALLOW_UNFREE = "1";
  };

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
