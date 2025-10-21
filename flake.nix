{
  description = "rx.nix: Reactive Nix | Enabling Functional Reactive Configuration with mgmt";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ { self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ withSystem, flake-parts-lib, ... }: {
      flake = {
        overlays.default = final: prev: {
          options-generator = final.callPackage ./options-generator/package.nix { };
          generated-options = final.callPackage ./options-generator/options-package.nix { };
        };
        flakeModules.default = flake-parts-lib.importApply ./flake-module { inherit withSystem; };
        nixosModules.default = import ./nixos;
      };

      perSystem = { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
            config = { };
          };
        in
        {
          _module.args.pkgs = pkgs;
          packages = { inherit (pkgs) options-generator generated-options; };
        };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
        "i686-linux"
        "armv6l-linux"
        "armv7l-linux"
        "riscv64-linux"
      ];

    });
}

