{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {

    packages = [ pkgs.python3 ];

    shellHook = ''
        echo "Welcome to a python shell"
    '';

    ENV_VARIABLE_EXAMPLE = "Hello from the shell.nix";

    LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [ pkgs.python3 ]}";
}
