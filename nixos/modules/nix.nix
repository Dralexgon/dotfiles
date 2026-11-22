{ pkgs, username, ... }:

{
  # Beautiful rebuild switch animation (nh os switch), with the diff of the new
  # generation. nixcfg uses it for update, build and switch when installed.
  programs.nh = {
    enable = true;
    flake = "/home/${username}/dotfiles";
  };

  environment.systemPackages = with pkgs; [
    # Simple useful tools for Nixos
    nix-output-monitor # nom: the same build tree as nh, for any nix build
    nvd # View package difference between generations
    # Example:
    # - nvd history
    # nvd diff /nix/var/nix/profiles/system-{42,43}-link
    nil # Nix lsp (language server protocol) for errors and warnings in .nix files
  ];
}