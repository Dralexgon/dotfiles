{ pkgs, ... }:

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

  environment.systemPackages = with pkgs; [
    nvtopPackages.amd # TUI that displays GPU usage
  ];
}
