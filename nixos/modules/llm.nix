{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    open-webui
    ollama-cuda
  ];
}