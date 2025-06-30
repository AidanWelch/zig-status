{
  description = "Basic status info in the i3bar/swaybar protocol";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    zig-overlay,
  }:
    builtins.foldl' nixpkgs.lib.recursiveUpdate {} (
      builtins.map
      (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
          zig = zig-overlay.packages.${system}.master;
          target = builtins.replaceStrings ["darwin"] ["macos"] system;
          zig-status = pkgs.stdenvNoCC.mkDerivation {
            name = "zig-status";
            nativeBuildInputs = [zig];
            dontConfigure = true;
            dontInstall = true;
            doCheck = true;
            src = self;
            buildPhase = ''
              PACKAGE_DIR=${pkgs.callPackage ./deps.nix {}}
              zig build install --global-cache-dir $(pwd)/.cache --system $PACKAGE_DIR -Dtarget=${target} -Doptimize=ReleaseSafe --color off --prefix $out
            '';
            checkPhase = ''
              zig build test --global-cache-dir $(pwd)/.cache --system $PACKAGE_DIR -Dtarget=${target} --color off
            '';
          };
        in {
          formatter.${system} = pkgs.alejandra;
          packages.${system} = rec {
            default = zig-status;
            inherit zig-status;
          };
        
          apps = rec {
            default = zig-status;
            zig-status = zig-status;
          };
        }
      )
      ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"]
    );
}
