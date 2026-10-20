# sudo su
# linux partition: mount /dev/nvme... /mnt
# efi partition: mount /dev/nvme... /mnt/boot
# nixos-enter
nixos-rebuild boot --flake .#nixos-tower-RTX3060 --install-bootloader --option sandbox false
