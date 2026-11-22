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
    # nil (Nix lsp) and the jetbrains-mono font are in core.nix
  ];
}