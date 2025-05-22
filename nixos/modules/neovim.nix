{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Neovim packages
    neovim
    lua
    cargo
    # jetbrains-mono
    # font-awesome
    luarocks
    lazygit
    fd
    wl-clipboard
    ripgrep
    nodejs # For copilot nvim
    nil # Nix lsp (language server protocol) for errors and warnings in .nix files
  ];

  fonts.packages = with pkgs; [
    jetbrains-mono
    # font-awesome
  ];
}