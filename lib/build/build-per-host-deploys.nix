{ irByHost, pkgs }:

let
  mkDeploy = import ./mkDeploy.nix;
  pkgs' = pkgs.extend (final: prev: {
    rx-codegen = final.callPackage ../../pkgs/codegen.nix { };
  });
in
pkgs.lib.mapAttrs
  (deployName: ir:
  let
    deployDrv = pkgs'.callPackage (mkDeploy { inherit ir deployName; }) { };
  in
  pkgs.callPackage ../../pkgs/deploy.nix { inherit deployName deployDrv; }
  )
  irByHost
