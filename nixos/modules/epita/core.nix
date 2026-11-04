{ pkgs, ... }:

{
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
