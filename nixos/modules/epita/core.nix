{ pkgs, ... }:

{

  imports = [
    # ./android.nix
    ./c.nix
    ./criterion.nix
    # ./cpp.nix
    ./docker.nix
    # ./image.nix
    ./java.nix
    # ./js.nix
    # ./net.nix
  ];

  environment.systemPackages = with pkgs; [
    # Man pages
    man-pages
    man-pages-posix

    # # Afs
    # krb5
    # sshfs

    # Mail
    thunderbird
  ];
}
