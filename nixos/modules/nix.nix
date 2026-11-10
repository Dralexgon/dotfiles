{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Simple useful tools for Nixos
    nh # Beautiful rebuild switch animation (nh os rebuild)
    nix-output-monitor # Same but work with more things
    nvd # View package difference between generations
    # Example:
    # - nvd history
    # nvd diff /nix/var/nix/profiles/system-{42,43}-link
    nil # Nix lsp (language server protocol) for errors and warnings in .nix files
  ];
}