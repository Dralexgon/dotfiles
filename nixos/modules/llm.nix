{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    ollama-cuda
    opencode
  ];

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