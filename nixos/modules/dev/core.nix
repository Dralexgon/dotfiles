{ pkgs, pkgs-stable, ... }:

{
  imports = [
    ./neovim.nix
    # ./jetbrains.nix
    # ./game-creation.nix
  ];

  environment.systemPackages = with pkgs; [
    vim
    # neovim # enable ./neovim.nix to use lazyvim

    # Vscode and forks
    pkgs-stable.vscode
    vscodium

    nil # Nix lsp (language server protocol) for errors and warnings in .nix files
  ];
}
