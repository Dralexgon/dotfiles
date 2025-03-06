{
  description = "Nixos config flake";

  inputs = {
    # Change depending on your prefered version
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";


    nix-minecraft.url = "github:Infinidoge/nix-minecraft";
    boot-animation.url = "github:Melkor333/nixos-boot";
    # catppuccin.url = "github:catppuccin/nix";
    # home-manager = {
    #   url = "github:nix-community/home-manager";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs,  ... }@inputs: {

    nixosConfigurations."nixos" = self.nixosConfigurations."host-RTX3060-alex";

    nixosConfigurations."host-RTX3060-alex" = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs;};
      modules = [
        ./nixos/configuration.nix

        inputs.boot-animation.nixosModules.default
        # inputs.home-manager.nixosModules.default

        # catppuccin.nixosModules.catppuccin
        # home-manager.nixosModules.home-manager

        # {
        #   home-manager.users.alex = {
        #     imports = [
        #       ./nixos/home.nix
        #       catppuccin.homeManagerModules.catppuccin
        #     ];
        #   };
        # }

      ];
    };

    # homeConfigurations.pepperjack = home-manager.lib.homeManagerConfiguration {
    #   pkgs = nixpkgs.legacyPackages.x86_64-linux;
    #   modules = [
    #     ./home.nix
    #     catppuccin.homeManagerModules.catppuccin
    #   ];
    # };
  };
}
