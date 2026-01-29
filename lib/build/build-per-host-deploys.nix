{ irByHost, pkgs }:

let
  pkgs' = pkgs.extend (final: prev: {
    rx-codegen = final.callPackage ../../pkgs/codegen.nix { };
  });
in
pkgs.lib.mapAttrs
  (deployName: ir:
  let
    moduleDrv = pkgs'.callPackage (import ../../pkgs/module.nix { inherit ir deployName; }) { };
  in
  pkgs.callPackage ../../pkgs/generation.nix { inherit deployName moduleDrv; }
  )
  irByHost
