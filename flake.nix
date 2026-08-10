{
  description = "Helium browser flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        pname = "helium-browser";
        version = "0.15.3.1";

        linuxHelium =
        let
          linuxArch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64";
          linuxHashes = {
            x86_64 = "sha256-IEYWTZ48ioufDCdzXgGy/TZw3dHh45mqZuPW0j3DoYY=";
            arm64 = "sha256-/7S176593jli0rSExhATwNx3ZcVkrwuQlZ0dU7tMPjU=";
          };
          linuxSrc = pkgs.fetchurl {
            url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-${linuxArch}_linux.tar.xz";
            sha256 = linuxHashes.${linuxArch};
          };
          deps = with pkgs; [
            stdenv.cc.cc
            nss
            nspr
            libGL
            libgbm
            libdrm
            libxkbcommon
            libX11
            libXcomposite
            libXdamage
            libXext
            libXfixes
            libXrandr
            libXrender
            libxcb
            libxshmfence
            libXi
            libXcursor
            libXft
            libXScrnSaver
            libXtst
            libSM
            libICE
            libXt
            alsa-lib
            dbus
            cups
            ffmpeg
            libva
            pipewire
            wayland
            vulkan-loader
            systemd
            pango
            cairo
            gdk-pixbuf
            atk
            at-spi2-atk
            at-spi2-core
            freetype
            fontconfig
            libuuid
            expat
            zlib
            libxml2
            gtk3
            glib
            libkrb5
            snappy
            udev
            qt5.qtbase
            qt6.qtbase
            qt6.qtwayland
          ];
          libPath = lib.makeLibraryPath deps
            + ":${lib.makeSearchPathOutput "lib" "lib64" deps}"
            + ":$out/opt/${pname}";
        in
        pkgs.stdenv.mkDerivation {
          inherit pname version;
          src = linuxSrc;

          dontConfigure = true;
          dontBuild = true;
          dontPatchELF = true;
          dontStrip = true;

          nativeBuildInputs = [ pkgs.makeWrapper pkgs.patchelf ];

          installPhase = ''
            runHook preInstall

            mkdir -p "$out/opt/${pname}"
            cp -r . "$out/opt/${pname}/"

            for bin in helium helium_crashpad_handler chromedriver; do
              if [ -f "$out/opt/${pname}/$bin" ]; then
                patchelf \
                  --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
                  --set-rpath "${libPath}" \
                  "$out/opt/${pname}/$bin"
              fi
            done

            mkdir -p "$out/bin"
            makeWrapper "$out/opt/${pname}/helium" "$out/bin/${pname}" \
              --prefix LD_LIBRARY_PATH : "${libPath}"

            install -Dm444 helium.desktop "$out/share/applications/${pname}.desktop"
            sed -i \
              -e "s|^Exec=.*|Exec=$out/bin/${pname} %U|" \
              -e "s|^Icon=.*|Icon=${pname}|" \
              "$out/share/applications/${pname}.desktop"

            install -Dm444 product_logo_256.png "$out/share/pixmaps/${pname}.png"

            runHook postInstall
          '';

          meta = with lib;{
            description = "Private, fast, and honest web browser";
            homepage = "helium.computer";
            license = licenses.gpl3Only;
            platforms = platforms.linux;
            mainProgram = pname;
          };
        };

        darwinHelium =
        let
          darwinSrc = pkgs.fetchurl {
            url = "https://github.com/imputnet/helium-macos/releases/download/${version}/helium_${version}_arm64-macos.dmg";
            sha256 = "sha256-JOBiYoQmtcZLZLAWroTVn0Eff5EntD2UgJKRP/E4aZ8=";
          };
        in
        pkgs.stdenv.mkDerivation {
          inherit pname version;
          src = darwinSrc;

          nativeBuildInputs = [ pkgs._7zz ];

          unpackPhase = ''
            runHook preUnpack
            7zz x "$src" || true
            runHook postUnpack
          '';
          sourceRoot = ".";

          installPhase = ''
            runHook preInstall

            app=$(find . -maxdepth 1 -name "*.app" -print -quit)
            if [ -z "$app" ]; then
              echo "error: no .app bundle found in the dmg" >&2
              exit 1
            fi

            mkdir -p "$out/Applications"
            cp -R "$app" "$out/Applications/Helium.app"

            codesign --force --deep --sign - "$out/Applications/Helium.app" || true

            mkdir -p "$out/bin"
            cat > "$out/bin/${pname}" <<EOF
            #!/bin/sh
            exec /usr/bin/open -na "$out/Applications/Helium.app" --args "\$@"
            EOF
            chmod +x "$out/bin/${pname}"

            runHook postInstall
          '';

          meta = with lib;{
            description = "Private, fast, and honest web browser";
            homepage = "helium.computer";
            license = licenses.gpl3Only;
            platforms = platforms.darwin;
            mainProgram = pname;
          };
        };

        helium = if pkgs.stdenv.isDarwin then darwinHelium else linuxHelium;
      in
     {
       packages.default = helium;
       packages.${pname} = helium;
       apps.default = {
         type = "app";
         program = "${helium}/bin/${pname}";
       };
     });
}
