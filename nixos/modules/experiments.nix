{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    ollama-cuda
    # Doesn't seem to work:
    # (alpaca.override { ollama = pkgs.ollama-cuda; })
  ];
}