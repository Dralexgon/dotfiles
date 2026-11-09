# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, inputs, ... }:

let
  # older way: nixpkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
  pkgs-stable = import inputs.nixpkgs-stable { system = pkgs.stdenv.hostPlatform.system; config.allowUnfree = true; };
  # use it as pkgs-stable.example
  useGrub = false; # Set to false if you don't want to use my grub theme or prefer systemd-boot
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
      enable = useGrub;
      efiSupport = true;
      device = "nodev";
      useOSProber = true;
      theme = pkgs.catppuccin-grub;
      extraConfig = ''
        menuentry "UEFI Firmware Settings" {
          fwsetup
        }
      '';
    };
    systemd-boot.enable = !useGrub; # Default boot loader
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings.auto-optimise-store = true;
  boot.loader.systemd-boot.configurationLimit = 10;



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

  # GitHub HTTPS credentials through gh, found on PATH: `gh auth setup-git` writes a /nix/store path
  # into ~/.gitconfig that breaks once gh updates and the old store path is garbage-collected.
  # Don't run `gh auth setup-git` (and answer no to it in `gh auth login`).
  programs.git = {
    enable = true;
    config.credential = {
      "https://github.com".helper = [ "" "!gh auth git-credential" ];
      "https://gist.github.com".helper = [ "" "!gh auth git-credential" ];
    };
  };

  fonts.packages = with pkgs; [
    jetbrains-mono
  ];

  # fonts.fontDir.enable = true;

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # Libraries expected to be in /usr/lib
      # curl.dev
      clang-tools
      criterion # doesn't work here, use modules/epita/criterion.nix instead
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # Web browsers
    firefox
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    # tor-browser
    # brave
    # chromium

    # Text editors/IDE
    vim
    pkgs-stable.vscode
    vscodium
    # or activate modules/jetbrains.nix in configuration.nix

    # Terminal <3 meow
    kitty # In kitty.conf set linux_display_server to x11 to have the same look as gnome-terminal
    # Set font to JetBrains Mono Nerd Font Mono if you want to use nerd fonts

    # TUI to toggle modules and packages (also in the app launcher)
    (import ../tools/nixcfg { inherit pkgs; })

    # Nova (voice AI companion, ~/dev/ai/nova) in the app launcher.
    # Same as SUPER + A: toggles her if she runs, starts her otherwise.
    (pkgs.makeDesktopItem {
      name = "nova";
      desktopName = "Nova";
      genericName = "Voice AI companion";
      comment = "Talk with Nova";
      exec = "${pkgs.writeShellScript "nova-launch" ''
        ${pkgs.curl}/bin/curl -sf -X POST http://127.0.0.1:8765/api/toggle \
          || exec "$HOME/dev/ai/nova/run.sh"
      ''}";
      icon = "audio-input-microphone";
      categories = [ "Utility" ];
      keywords = [ "nova" "ai" "voice" "assistant" "claude" ];
    })

    # Simple useful tools
    git
    gh # GitHub CLI (gh auth login, gh auth setup-git)
    tree
    tldr # better man (man pages)
    wget
    unzip
    xkill

    # Simple useful tools for Nixos
    nh # Beautiful rebuild switch animation (nh os rebuild)
    nix-output-monitor # Same but work with more things
    nvd # View package difference between generations
    # Example:
    # - nvd history
    # nvd diff /nix/var/nix/profiles/system-{42,43}-link
    nil # Nix lsp (language server protocol) for errors and warnings in .nix files

    # 2 discord clients for multiple accounts
    # discord
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





  #########################################
  # Mandatory options that I never change #
  #########################################

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Enable networking
  networking.networkmanager.enable = true;

  # Bluetooth
  hardware.bluetooth.enable = true;
  # services.blueman.enable = true; # Gui if you Desktop Environment doesn't have it

  # Set your time zone.
  time.timeZone = "Europe/Paris";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.brlaser pkgs.brgenml1lpr pkgs.brgenml1cupswrapper ];

  # OneDrive sync (abraunegg client). First login: run `onedrive` once.
  # Choose folders in ~/.config/onedrive/sync_list
  services.onedrive.enable = false;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false; # hardware.pulseaudio.enable = false; # old versions
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    jack.enable = true;

    wireplumber.enable = true;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Allow unfree packages v2 (not sure if it works)
  environment.variables = {
    NIXPKGS_ALLOW_UNFREE = "1";
    NIXPKGS_ALLOW_INSECURE = "1";
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
