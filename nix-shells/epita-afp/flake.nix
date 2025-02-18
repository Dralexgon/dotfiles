{
  description = "Compilateurs haskell et lisp pour Approches Fonctionnelles de la Programmation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = nixpkgs.legacyPackages."x86_64-linux";
  in
  {
    devShell."x86_64-linux" = pkgs.mkShell
    {
      packages = [
        pkgs.haskellPackages.ghc
      ];

      shellHook = ''
        echo "${description}"
      '';
    };
  };
}
