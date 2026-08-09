{
  description = "Helium AppImage wrapper flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) makeWrapper;

        pname = "helium-browser";
        version = "0.15.3.1";
        extraFlags = "--password-store=basic";

        src = pkgs.fetchurl {
          url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
          sha256 = "sha256-ZCCm/prkgYgbDHW6OBPWvoIE77g7IYQpYdqc/PnIrSU=";
        };

        extracted = pkgs.appimageTools.extract {
          inherit pname version src;
        };

        desktopItem = pkgs.makeDesktopItem {
          name = pname;
          desktopName = "Helium";
          comment = "Web browser";
          exec = "${pname} ${extraFlags} %U";
          terminal = false;
          categories = [ "Network" "WebBrowser" ];
          icon = pname;
          startupWMClass = "helium-browser";
        };

        radeonEnvScript = ''
          for vendor_file in /sys/class/drm/card*/device/vendor; do
            if [ -f "$vendor_file" ] && [ "$(cat "$vendor_file" 2>/dev/null)" = "0x1002" ]; then
              export LIBVA_DRIVER_NAME=radeonsi
              export LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri
              export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json
              break
            fi
          done
        '';

        helium = pkgs.appimageTools.wrapType2 {
          inherit pname version src;

          extraPkgs = pkgs: with pkgs; [
            libva
            mesa
            libGL
            vulkan-loader
          ];

          extraEnv = {
            NIXOS_OZONE_WL = "1";
          };

          extraInstallCommands = ''
            source "${makeWrapper}/nix-support/setup-hook"

            install -Dm444 ${desktopItem}/share/applications/${pname}.desktop \
              -t "$out/share/applications"

            install -Dm444 ${extracted}/.DirIcon \
              $out/share/pixmaps/${pname}.png

            wrapProgram $out/bin/${pname} \
              --add-flags "${extraFlags}" \
              --run ${pkgs.lib.escapeShellArg radeonEnvScript}
          '';
        };
      in {
        packages.default = helium;
        packages.${pname} = helium;

        apps.default = {
          type = "app";
          program = "${helium}/bin/${pname}";
        };
      });
}
