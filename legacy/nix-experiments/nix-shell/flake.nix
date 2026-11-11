{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = nixpkgs.legacyPackages."x86_64-linux";
  in
  {
    devShell."x86_64-linux" = pkgs.mkShell {
      packages = [ pkgs.python3 ];

      shellHook = ''
          echo "Welcome to a python shell"
      '';

      ENV_VARIABLE_EXAMPLE = "Hello from the shell.nix";

      LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [ pkgs.python3 ]}";
    };
  };
}
