{
  description = "QOI encoder & decoder in zig";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    utils.url = github:numtide/flake-utils;
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";

        buildInputs = with pkgs; [
          zig
        ];
      in
      rec {
        # `nix build`
        packages = {
          qoi-zig = pkgs.stdenv.mkDerivation {
            inherit buildInputs;
            name = "qoi-zig";
            src = self;

            installPhase = ''
              zig build
            '';
          };
        };
        defaultPackage = packages.qoi-zig;

        # `nix run`
        apps.qoi-zig = utils.lib.mkApp {
          drv = packages.qoi-zig;
        };
        defaultApp = apps.qoi-zig;

        # `nix develop`
        devShell = pkgs.mkShell {
          inherit buildInputs;
        };
      });
}
