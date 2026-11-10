# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, pkgs-stable, inputs, username, ... }:

let
  useGrub = false; # Set to false if you don't want to use my grub theme or prefer systemd-boot

  # Packages that aren't in nixpkgs, named so that they are plain lines of
  # environment.systemPackages (and can be toggled with nixcfg). A let name
  # wins over `with pkgs;`.
  zen-browser = inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # TUI to toggle modules and packages (also in the app launcher)
  nixcfg = import ../tools/nixcfg { inherit pkgs; };

  # Nova (voice AI companion, ~/dev/ai/nova) in the app launcher.
  # Same as SUPER + A: toggles her if she runs, starts her otherwise.
  nova = pkgs.makeDesktopItem {
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
  };
in

{
  imports = [
    # Desktops: options to pick them per host (desktop.enabled)
    ./modules/desktop

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
      # criterion (testsuites for C programs) is in criterion.nix
    ];
  };

  # NixOS defaults EDITOR to nano for every session; the bashrc's nvim only
  # reaches interactive bash, not apps started from the launcher (like nixcfg).
  environment.variables.EDITOR = "nvim";
  environment.variables.VISUAL = "nvim";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    firefox # Always useful to have at least one browser, you can add more in ./modules/browsers.nix

    # Text editors/IDE
    vim
    pkgs-stable.vscode
    vscodium

    # Terminal <3 meow
    kitty # In kitty.conf set linux_display_server to x11 to have the same look as gnome-terminal
    # Set font to JetBrains Mono Nerd Font Mono if you want to use nerd fonts

    # TUI to toggle modules and packages (also in the app launcher)
    nixcfg

    # Nova (voice AI companion, ~/dev/ai/nova) in the app launcher
    nova

    # Simple useful tools
    git
    gh # GitHub CLI (gh auth login, gh auth setup-git)
    tree
    tldr # better man (man pages)
    wget
    unzip
    xkill

    # 2 discord clients for multiple accounts
    # discord
    vesktop
  ];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [ "networkmanager" "wheel" ];
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
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
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

  # Allow unfree packages (for nix-shell / nix run outside this flake: NIXPKGS_ALLOW_UNFREE=1 ... --impure)
  nixpkgs.config.allowUnfree = true;

  # Enable experimental features like flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # system.stateVersion is set in each host configuration.nix
}
