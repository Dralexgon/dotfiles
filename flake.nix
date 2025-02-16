{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nix-minecraft.url = "github:Infinidoge/nix-minecraft";
    # my-alex-test.url = "github:nixos/nixpkgs/nixos-unstable";
    catppuccin.url = "github:catppuccin/nix";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, catppuccin, home-manager, ... }@inputs: {
    nixosConfigurations.alex = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs;};
      modules = [
        ./nixos/configuration.nix
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
