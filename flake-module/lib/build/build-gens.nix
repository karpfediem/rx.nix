{ irByHost, pkgs }:

let
  mkDeploy = import ./mkDeploy.nix;
  writeSwitch = import ./write-switch.nix {
    mgmtBin = "${pkgs.mgmt}/bin/mgmt";
    profilePath = "/nix/var/nix/profiles/mgmt/current";
  };
  writeRollback = import ./write-rollback.nix { profilePath = "/nix/var/nix/profiles/mgmt/current"; };

  pkgs' = pkgs.extend (final: prev: {
    rx-codegen = final.callPackage ../../../pkgs/codegen.nix { };
  });
in
pkgs.lib.mapAttrs
  (name: ir:
  let
    deployDrv = pkgs'.callPackage (mkDeploy { inherit ir name; }) { };
  in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "rxnix-gen-${name}";
    version = "0.0.1";
    preferLocalBuild = true;
    allowSubstitutes = false;
    buildCommand = ''
              set -euo pipefail
              mkdir -p "$out"

              # Canonical payload for this generation.
              ln -s "${deployDrv}/deploy" "$out/deploy"

              # switcher: link profile (nix-env --set), bounce service or run once
              cat > "$out/switch-to-configuration" <<'SH'
      ${writeSwitch}
      SH
              chmod +x "$out/switch-to-configuration"

              # rollback helper for this profile
              cat > "$out/rollback" <<'SH'
      ${writeRollback}
      SH
              chmod +x "$out/rollback"
    '';
  }
  )
  irByHost
