# My dotfiles (Not finished !)

[![Watch the video](https://img.youtube.com/vi/rfYjSGmUcBk/maxresdefault.jpg)](https://youtu.be/rfYjSGmUcBk)

## Install GTK theme + icon theme

For Nix/Nixos user:
```
git clone https://github.com/Dralexgon/dotfiles
./dotfiles/scripts/apply-gnome-nix.sh
```

For other distro install:

- install `sassc` (example: on ubuntu `sudo apt install sassc`)

OR

- install `nix` (example: `sh <(curl -L https://nixos.org/nix/install) --no-daemon`)

## Install the whole system with NixOS

`sudo nixos-rebuild switch --flake github:Dralexgon/dotfiles#default`