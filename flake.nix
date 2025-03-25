{
  description = "Nixos config flake";

  inputs = {
    # Change depending on your prefered version
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixpkgs23.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs24.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    #stylix.url = "github:danth/stylix";
    #nix-minecraft.url = "github:Infinidoge/nix-minecraft";
    #boot-animation.url = "github:Melkor333/nixos-boot";
    # catppuccin.url = "github:catppuccin/nix";
    # home-manager = {
    #   url = "github:nix-community/home-manager";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs,  ... }@inputs:{

    nixosConfigurations.default = self.nixosConfigurations."nixos";

    nixosConfigurations."nixos" = self.nixosConfigurations."nixos-tower-RTX3060";

    nixosConfigurations."nixos-tower-RTX3060" = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs;};
      modules = [
        ./nixos/configuration.nix
        ./nixos/modules/epita.nix
        ./nixos/modules/gaming.nix
        ./nixos/modules/nvidia-drivers.nix
        ./nixos/modules/razer.nix
        ./nixos/modules/swap.nix
        ./nixos/modules/ricing.nix
        ./nixos/modules/ricing-tools.nix

        # inputs.boot-animation.nixosModules.default
      ];
    };

    nixosConfigurations."nixos-grey-laptop" = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs;};
      modules = [
        ./nixos/configuration.nix
        ./nixos/modules/epita.nix
        #./nixos/modules/gaming.nix
        #./nixos/modules/nvidia-drivers.nix
        #./nixos/modules/razer.nix
        ./nixos/modules/swap.nix
        ./nixos/modules/ricing.nix
        ./nixos/modules/ricing-tools.nix

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
