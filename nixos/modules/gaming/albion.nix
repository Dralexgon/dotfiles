{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # base
      libx11
      libxcursor
      libxrandr
      libxi
      libxext
      libxinerama
      libxxf86vm
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
      libxcb
      libxcb-util
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
      libxcb-wm
      libxcomposite
      libxdamage
      libxfixes
      libxrender
      libxtst
      libxscrnsaver
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
      libxau
      libxdmcp

      libgpg-error
      e2fsprogs   # provides libcom_err
      krb5        # also ships libcom_err, pulled in by curl/gssapi

      libxkbfile
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
