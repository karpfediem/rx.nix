{
  description = "rx.nix: Reactive nix | Closed loop automation using mgmt engine";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ { self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ withSystem, flake-parts-lib, ... }:
      let
        inherit (flake-parts-lib) importApply;
        flakeModules.default = importApply ./flake-module { inherit withSystem; };
        nixosModules.default = import ./nixos;
      in
      {
        systems = ["x86_64-linux"];

        flake = {
          inherit flakeModules;
          inherit nixosModules;
        };
      });
}

