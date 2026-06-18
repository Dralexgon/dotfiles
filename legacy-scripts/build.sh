./update-hardware-conf.sh

sudo nixos-rebuild boot --flake . --impure
#gnome-shell --replace #should reload desktop entries and app icons
