{ pkgs, pkgs-stable, ... }:

{
  # Simple useful apps
  environment.systemPackages = with pkgs; [
    libreoffice # Office suite
    drawing # Paint
    clapper # Video player
    eyedropper # Color picker
    pkgs-stable.amberol # Music player
    eartag # Music tag editor
    papers # PDF viewer
    inspector # "About your computer" app
    fragments # Bit torrent client
    gpu-screen-recorder # Screen recorder that use GPU for encoding (much better performance)
  ];
}
