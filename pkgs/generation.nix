{ deployName
, moduleDrv
, profilePath ? "/nix/var/nix/profiles/mgmt/current"
, callPackage
, stdenvNoCC
}:
let
  switchDrv = callPackage ./switch-to-configuration.nix { inherit profilePath; };
  rollbackDrv = callPackage ./rollback.nix { inherit profilePath; };
in
stdenvNoCC.mkDerivation {
  pname = "rx-gen-${deployName}";
  version = "0.0.1";
  preferLocalBuild = true;
  allowSubstitutes = false;
  buildCommand = ''
    set -euo pipefail
    mkdir -p "$out"
    cp -r "${moduleDrv}/deploy" "$out/deploy"
    cp "${switchDrv}/bin/switch-to-configuration" "$out/switch-to-configuration"
    cp "${rollbackDrv}/bin/rollback" "$out/rollback"
  '';
}
