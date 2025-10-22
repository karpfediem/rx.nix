{ lib }:
pkgs: irByHost:
let
  mclFromIr    = import ./codegen/mcl-from-ir.nix { inherit lib; };
  writeDeploy  = import ./codegen/write-deploy.nix { inherit lib; };
  writeSwitch = import ./build/write-switch.nix { mgmtBin = "${pkgs.mgmt}/bin/mgmt"; };
in
lib.mapAttrs (host: filesIR:
  let
    deploy = writeDeploy {
      inherit pkgs filesIR;
      name    = host;
      mclText = mclFromIr filesIR;
    };
  in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "rxnix-gen-${host}";
    version = "0.0.1";
    preferLocalBuild = true;
    allowSubstitutes = false;
    buildCommand = ''
      set -euo pipefail
      mkdir -p "$out"

      # Mount the deploy as the canonical payload for this generation.
      ln -s "${deploy}/deploy" "$out/deploy"

      # A manifest (debug) and a convenience symlink:
      ln -s "${deploy}/manifest.json" "$out/manifest.json"

      # switcher: link profile, bounce the service if present, else run once
      cat > "$out/switch-to-configuration" <<'SH'
${writeSwitch}
SH
      chmod +x "$out/switch-to-configuration"
    '';
  }
) irByHost
