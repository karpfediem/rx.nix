{ irByHost, pkgs }:

let
  mkDeploy = import ./mkDeploy.nix;
  writeSwitch = import ./write-switch.nix { mgmtBin = "${pkgs.mgmt}/bin/mgmt"; };
  pkgs' = pkgs.extend (final: prev: { rx-codegen = final.callPackage ../../../pkgs/codegen.nix { };} );
in
pkgs.lib.mapAttrs
  (name: ir:
  let
    deployDrv = pkgs'.callPackage (mkDeploy { inherit ir name; }) {};
  in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "rxnix-gen-${name}";
    version = "0.0.1";
    preferLocalBuild = true;
    allowSubstitutes = false;
    buildCommand = ''
            set -euo pipefail
            mkdir -p "$out"

            # Mount the deploy as the canonical payload for this generation.
            ln -s "${deployDrv}/deploy" "$out/deploy"

            # A manifest (debug) and a convenience symlink:
            ln -s "${deployDrv}/manifest.json" "$out/manifest.json"

            # switcher: link profile, bounce the service if present, else run once
            cat > "$out/switch-to-configuration" <<'SH'
      ${writeSwitch}
      SH
            chmod +x "$out/switch-to-configuration"
    '';
  }
  )
  irByHost
