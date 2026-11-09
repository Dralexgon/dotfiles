{ pkgs, ... }:

{
  imports = [
    # ./android.nix
    ./c.nix
    # ./cpp.nix
    ./criterion.nix
    ./docker.nix
    # ./image.nix
    # ./java.nix
    # ./js.nix
    ./latex.nix
    # ./net.nix
  ];

  programs.ssh.package = pkgs.openssh_gssapi; # add GSSAPI support

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
