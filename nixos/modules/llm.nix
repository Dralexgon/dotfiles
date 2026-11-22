{ pkgs, pkgs-stable, ... }:

{
  imports = [
    ./epita/docker.nix
  ];

  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm; # AMD GPU (RX 9070 XT is gfx1201, built by nixpkgs ROCm)
  };

  environment.systemPackages = with pkgs; [
    # upstream node_modules hash is stale in nixpkgs, remove once fixed
    (opencode.overrideAttrs (old: {
      node_modules = old.node_modules.overrideAttrs {
        outputHash = "sha256-prx9dX7kUvs/E3zopkaPk5LXh3xJAy5sZeum/W8L7cA=";
      };
    }))
    pkgs-stable.open-webui
    docker-compose
    (pkgs.stable-diffusion-cpp.override { vulkanSupport = true; })

    python3
    uv
    portaudio
    ffmpeg
    alsa-utils

    claude-code
  ];

  # programs.nix-ld.enable = true;   # lets pip wheels (ctranslate2, onnxruntime) run

  # services.ollama = {
  #   enable = true;
  #   environmentVariables = {
  #     OLLAMA_CONTEXT_LENGTH = "32768";
  #     OLLAMA_FLASH_ATTENTION = "1";
  #     OLLAMA_KV_CACHE_TYPE = "q8_0";  # roughly halves KV cache memory
  #   };
  # };

}