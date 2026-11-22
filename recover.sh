# sudo su
# linux partition: mount /dev/nvme... /mnt
# efi partition: mount /dev/nvme... /mnt/boot
# nixos-enter
nixos-rebuild boot --flake .#nixos-tower-RX9070XT --install-bootloader --option sandbox false
