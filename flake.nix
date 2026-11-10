{
  description = "Nixos config flake";

  inputs = {
    # Change depending on your prefered version
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";


    nixpkgs23.url = "github:nixos/nixpkgs/nixos-23.11";
    # nixpkgs24.url = "github:nixos/nixpkgs/nixos-24.11";
    # nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    #stylix.url = "github:danth/stylix";
    #nix-minecraft.url = "github:Infinidoge/nix-minecraft";
    #boot-animation.url = "github:Melkor333/nixos-boot";
    # catppuccin.url = "github:catppuccin/nix";
    # home-manager = {
    #   url = "github:nix-community/home-manager";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    quickshell = {
      # add ?ref=<tag> to track a tag
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";

      # THIS IS IMPORTANT
      # Mismatched system dependencies will lead to crashes and other issues.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-cli = {
      url = "github:caelestia-dots/cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        # IMPORTANT: To ensure compatibility with the latest Firefox version, use nixpkgs-unstable.
        nixpkgs.follows = "nixpkgs";
        # home-manager.follows = "home-manager";
      };
    };

    # Liquid Glass / Acrylic / Mica window effects, a Hyprland plugin built by tools/hypr-liquid
    # against pkgs.hyprland (its own flake pins another Hyprland), so only its source is used.
    hyprliquid = {
      url = "github:zaregototsukai/hyprliquid";
      flake = false;
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      # url = "github:nix-community/lanzaboote/0403b4b7e8b2612657f0053a4c315e6c43eee9e6";
      url = "github:nix-community/lanzaboote/v1.1.0";


      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
      # Its pinned rust-overlay still uses the deprecated stdenv.isLinux / isDarwin.
      inputs.rust-overlay.follows = "rust-overlay";
    };
  };


  outputs = { self, nixpkgs, nvf, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    nixcfg = import ./tools/nixcfg { inherit pkgs; };
    razerfx = import ./tools/razerfx { inherit pkgs; };

    # Given to every module as arguments, next to pkgs, config, lib...
    specialArgs = {
      inherit inputs;
      username = "alex";
      # Evaluated once here, instead of once per module that imports them.
      # Use them as pkgs-stable.example
      pkgs-stable = import inputs.nixpkgs-stable { inherit system; config.allowUnfree = true; };
      pkgs23 = import inputs.nixpkgs23 { inherit system; config.allowUnfree = true; }; # texliveFull
    };
  in
  {
    nixosConfigurations."nixos" = self.nixosConfigurations."default";

    nixosConfigurations."default" = nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      modules = [
        ./nixos/hosts/default/configuration.nix
      ];
    };

    nixosConfigurations."nixos-tower-RTX3060" = nixpkgs.lib.nixosSystem {
      # Main pc POWERFUL RTXXXX !!!
      inherit specialArgs;
      modules = [
        ./nixos/hosts/nixos-tower-RTX3060/configuration.nix
        # inputs.boot-animation.nixosModules.default
      ];
    };

    nixosConfigurations."nixos-gray-laptop" = nixpkgs.lib.nixosSystem {
      # Work laptop, nixos-gray-laptop: 50 nuance...
      inherit specialArgs;
      modules = [
        ./nixos/hosts/nixos-gray-laptop/configuration.nix

        # inputs.boot-animation.nixosModules.default
      ];
    };

    packages.${system}.default = (
      nvf.lib.neovimConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = [ ./nixos/home/nvf-config.nix ];
      }
    ).neovim;

    apps.${system} = {
      # TUI to toggle modules and packages per host: nix run ~/dotfiles#nixcfg
      nixcfg = {
        type = "app";
        program = "${nixcfg}/bin/nixcfg";
      };

      # Razer keyboard effects (TUI): nix run ~/dotfiles#razerfx
      razerfx = {
        type = "app";
        program = "${razerfx}/bin/razerfx";
      };
    };

    devShells.${system} = {
      # To work on nixcfg: nix develop ~/dotfiles#nixcfg, then
      # textual run --dev tools/nixcfg/nixcfg.py (live CSS reload, with textual console)
      nixcfg = pkgs.mkShell {
        packages = [
          (pkgs.python3.withPackages (p: nixcfg.pythonPackages p ++ [ p.textual-dev ]))
          pkgs.git
        ];
      };

      # To work on razerfx: nix develop ~/dotfiles#razerfx, then
      # python tools/razerfx/razerfx.py (stop the service first to run the daemon)
      razerfx = pkgs.mkShell {
        packages = [ (pkgs.python3.withPackages (p: razerfx.pythonPackages p ++ [ p.textual-dev ])) ];
      };
    };

    # nixosConfigurations."host-RTX3060-alex" = nixpkgs.lib.nixosSystem {
    #   specialArgs = {inherit inputs;};
    #   modules = [
    #     ./nixos/configuration.nix
    #
    #     inputs.boot-animation.nixosModules.default
    #     # inputs.home-manager.nixosModules.default
    #
    #     # catppuccin.nixosModules.catppuccin
    #     # home-manager.nixosModules.home-manager
    #
    #     # {
    #     #   home-manager.users.alex = {
    #     #     imports = [
    #     #       ./nixos/home.nix
    #     #       catppuccin.homeManagerModules.catppuccin
    #     #     ];
    #     #   };
    #     # }
    #
    #   ];
    # };

    # homeConfigurations.pepperjack = home-manager.lib.homeManagerConfiguration {
    #   pkgs = nixpkgs.legacyPackages.x86_64-linux;
    #   modules = [
    #     ./home.nix
    #     catppuccin.homeManagerModules.catppuccin
    #   ];
    # };
  };
}
