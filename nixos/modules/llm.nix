{ inputs, pkgs, ... }:

let
  # older way: nixpkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
  pkgs-stable = import inputs.nixpkgs-stable { system = pkgs.stdenv.hostPlatform.system; config.allowUnfree = true; };
in
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };

  virtualisation.docker.enable = true;
  users.users.alex.extraGroups = [ "docker" ];

  environment.systemPackages = with pkgs; [
    # upstream node_modules hash is stale in nixpkgs, remove once fixed
    (opencode.overrideAttrs (old: {
      node_modules = old.node_modules.overrideAttrs {
        outputHash = "sha256-prx9dX7kUvs/E3zopkaPk5LXh3xJAy5sZeum/W8L7cA=";
      };
    }))
    pkgs-stable.open-webui
    docker
    docker-compose
    (pkgs.stable-diffusion-cpp.override { vulkanSupport = true; })

    python3
    uv
    portaudio
    ffmpeg
    alsa-utils

    claude-code
  ];

  nix.settings = { # avoid compiling from source
    substituters = [ "https://cache.nixos-cuda.org" ];
    trusted-public-keys = [ "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" ];
  };

  # nixpkgs.config.allowUnfree = true;
  # hardware.graphics.enable = true;
  # services.xserver.videoDrivers = [ "nvidia" ];
  # hardware.nvidia = {
  #   open = true;            # fine for RTX 30xx
  #   modesetting.enable = true;
  #   package = config.boot.kernelPackages.nvidiaPackages.stable;
  # };

  # programs.nix-ld.enable = true;   # lets pip wheels (ctranslate2, onnxruntime) run

  # services.ollama = {
  #   enable = true;
  #   acceleration = "cuda";
  #   environmentVariables = {
  #     OLLAMA_CONTEXT_LENGTH = "32768";
  #     OLLAMA_FLASH_ATTENTION = "1";
  #     OLLAMA_KV_CACHE_TYPE = "q8_0";  # roughly halves KV cache memory
  #   };
  # };

}