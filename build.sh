if [ ! -e nixos/hardware-configuration.nix ] || ! diff nixos/hardware-configuration.nix /etc/nixos/hardware-configuration.nix; then
    sudo rm nixos/hardware-configuration.nix # &>/dev/null
    sudo nixos-generate-config --dir nixos
    sudo cp nixos/hardware-configuration.nix /etc/nixos/hardware-configuration.nix
fi

sudo nixos-rebuild boot --flake .#host-RTX3060-alex
