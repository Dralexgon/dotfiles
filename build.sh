if [ ! -e nixos/hardware-configuration.nix ]; then
    sudo nixos-generate-config --dir nixos
fi

sudo nixos-rebuild switch --flake .#alex
