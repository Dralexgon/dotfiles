{ pkgs, ... }:

{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };

  environment.systemPackages = with pkgs; [
    opencode

    python3
    uv
    portaudio
    ffmpeg
    alsa-utils
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