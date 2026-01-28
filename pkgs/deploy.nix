{ deployName
, deployDrv
, profilePath ? "/nix/var/nix/profiles/mgmt/current"
, stdenvNoCC
, bash
, nixVersions
, systemdMinimal
, coreutils-full
}:
let
  writeSwitch = import ../lib/build/write-switch.nix { inherit profilePath; };
  writeRollback = import ../lib/build/write-rollback.nix { inherit profilePath; };
in
stdenvNoCC.mkDerivation {
  pname = "rx-deploy-${deployName}";
  version = "0.0.1";
  preferLocalBuild = true;
  allowSubstitutes = false;

  propagatedBuildInputs = [
    bash
    nixVersions.latest
    systemdMinimal
    coreutils-full
  ];
  buildCommand = ''
          set -euo pipefail
          mkdir -p "$out"

          ln -s "${deployDrv}/deploy" "$out/deploy"

          cat > "$out/switch-to-configuration" <<'SH'
    ${writeSwitch}
    SH
          chmod +x "$out/switch-to-configuration"

          cat > "$out/rollback" <<'SH'
    ${writeRollback}
    SH
          chmod +x "$out/rollback"
  '';
}
