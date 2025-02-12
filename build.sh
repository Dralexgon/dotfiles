# if sudo nixos-rebuild boot --flake .#default 2>&1 | grep nixos/hardware-configuration.nix; then
#     sudo nixos-generate-config --dir nixos && exit
#     ./build.sh
# fi

if [ ! -e nixos/hardware-configuration.nix ]; then
    sudo nixos-generate-config --dir nixos
fi

sudo nixos-rebuild boot --flake .#default
