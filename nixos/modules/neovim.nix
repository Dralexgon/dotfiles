{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Neovim packages
    neovim
    lua
    cargo
    luarocks
    lazygit
    fd
    wl-clipboard
    ripgrep
    nodejs # For copilot nvim
    nil # Nix lsp (language server protocol) for errors and warnings in .nix files
    # jetbrains-mono # I prefere to use it in the fonts section
    # font-awesome # I prefere to use it in the fonts section
  ];

  fonts.packages = with pkgs; [
    jetbrains-mono
    # font-awesome
  ];
}