{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # base
      xorg.libX11
      xorg.libXcursor
      xorg.libXrandr
      xorg.libXi
      xorg.libXext
      xorg.libXinerama
      xorg.libXxf86vm
      libGL
      libglvnd
      vulkan-loader
      alsa-lib
      libpulseaudio
      udev
      openssl
      zlib
      glib
      gtk3
      gdk-pixbuf
      cairo
      pango
      atk
      nss
      nspr
      dbus
      fontconfig
      freetype
      libxkbcommon
      stdenv.cc.cc.lib

      # xcb / DRI
      xorg.libxcb
      xorg.xcbutil
      xorg.xcbutilimage
      xorg.xcbutilkeysyms
      xorg.xcbutilrenderutil
      xorg.xcbutilwm
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXfixes
      xorg.libXrender
      xorg.libXtst
      xorg.libXScrnSaver
      libdrm
      mesa
      libgbm
      wayland
      libxshmfence

      # next batch
      expat
      libuuid
      libbsd
      libsecret
      libnotify
      libappindicator-gtk3
      at-spi2-atk
      at-spi2-core
      cups
      libpng
      libjpeg
      libxml2
      curl
      icu
      libsndfile
      SDL2
      xorg.libXau
      xorg.libXdmcp

      libgpg-error
      e2fsprogs   # provides libcom_err
      krb5        # also ships libcom_err, pulled in by curl/gssapi

      xorg.libxkbfile
      libxslt
      libevent
      minizip
      snappy
      harfbuzz
      lcms2
      libwebp
      libopus
      pciutils

      sqlite
    ];
  };
}
