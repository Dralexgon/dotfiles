{
  description = "Nixos config flake";

  inputs = {
    # Change depending on your prefered version
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";


    # nixpkgs23.url = "github:nixos/nixpkgs/nixos-23.11";
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
  };


  outputs = { self, nixpkgs,  ... }@inputs:

  {

    nixosConfigurations."nixos" = self.nixosConfigurations."default";

    nixosConfigurations."default" = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs;};
      modules = [
        ./nixos/hosts/default/configuration.nix
      ];
    };

    nixosConfigurations."nixos-tower-RTX3060" = nixpkgs.lib.nixosSystem {
      # Main pc POWERFUL RTXXXX !!!
      specialArgs = {inherit inputs;};
      modules = [
        ./nixos/hosts/nixos-tower-RTX3060/configuration.nix

        # inputs.boot-animation.nixosModules.default
      ];
    };

    nixosConfigurations."nixos-grey-laptop" = nixpkgs.lib.nixosSystem {
      # Work laptop, nixos-grey-laptop: 50 nuance...
      specialArgs = {inherit inputs;};
      modules = [
        ./nixos/hosts/nixos-grey-laptop/configuration.nix

        # inputs.boot-animation.nixosModules.default
      ];
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
