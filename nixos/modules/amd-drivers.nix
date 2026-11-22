{ pkgs, username, ... }:

{
  # AMD GPU (RX 9070 XT, RDNA 4). The kernel driver (amdgpu) and Mesa (RADV Vulkan,
  # OpenGL, VA-API video encode/decode) are open source and built in, so there is
  # no driver package to pick like on NVIDIA.
  # RDNA 4 needs a recent kernel (6.13+) and firmware: see latest-kernel.nix.
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # 32-bit games (Steam, Wine)
  };
  hardware.enableRedistributableFirmware = true; # amdgpu firmware blobs

  # Load amdgpu in the initrd so plymouth gets the real framebuffer early
  # (same reason as the NVIDIA modules in boot-animation.nix)
  hardware.amdgpu.initrd.enable = true;

  # OpenCL through ROCm (Blender, darktable, ...)
  hardware.amdgpu.opencl.enable = true;

  # LACT: GUI to monitor and tune the GPU (fan curve, power limit, undervolt).
  # Overdrive unlocks the clock and voltage settings in it.
  services.lact.enable = true;
  hardware.amdgpu.overdrive.enable = true;

  # ROCm: AMD's compute stack (CUDA equivalent). Ollama already uses it (llm.nix).
  # Not setting nixpkgs.config.rocmSupport globally: it would rebuild half of
  # nixpkgs (PyTorch, Blender...) from source. Use per-package variants instead.
  users.users.${username}.extraGroups = [ "video" "render" ]; # access /dev/kfd and /dev/dri

  # Many tools (PyTorch wheels, ComfyUI, scripts) expect ROCm/HIP in /opt/rocm
  systemd.tmpfiles.rules =
    let
      rocmEnv = pkgs.symlinkJoin {
        name = "rocm-combined";
        paths = with pkgs.rocmPackages; [ rocblas hipblas clr ];
      };
    in
    [ "L+ /opt/rocm - - - - ${rocmEnv}" ];

  environment.systemPackages = with pkgs; [
    nvtopPackages.amd # TUI that displays GPU usage
    rocmPackages.rocminfo # list ROCm agents (should show gfx1201)
    rocmPackages.rocm-smi # GPU stats / clocks from ROCm
    rocmPackages.amdsmi # amd-smi, the newer replacement of rocm-smi
  ];
}
