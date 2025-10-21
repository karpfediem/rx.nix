{
  description = "rx.nix: Reactive Nix | Enabling Functional Reactive Configuration with mgmt";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ { self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ withSystem, flake-parts-lib, ... }: {
      systems = [ "x86_64-linux" ];

      perSystem = { config, pkgs, ... }: rec {
        packages.options-generator = pkgs.callPackage ./options-generator/package.nix { };
        packages.generated-options = pkgs.callPackage ./options-generator/options-package.nix { inherit (packages) options-generator; };
      };

      flake = {
        flakeModules.default = flake-parts-lib.importApply ./flake-module { inherit withSystem; };
        nixosModules.default = import ./nixos;
      };
    });
}

