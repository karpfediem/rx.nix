{ profilePath ? "/nix/var/nix/profiles/mgmt/current"
, pkgs
, bash
, nixVersions
, systemdMinimal
, coreutils-full
}: pkgs.writeShellApplication {
  name = "rollback";
  runtimeInputs = [
    bash
    nixVersions.latest
    systemdMinimal
    coreutils-full
  ];
  text = ''
    #!${bash}/bin/bash
    set -euo pipefail

    PROFILE="${profilePath}"

    # Roll back to the previous generation of the mgmt profile.
    # If you want to roll back multiple steps, pass a generation number:
    #   ${nixVersions.latest}/bin/nix-env --profile "$PROFILE" --list-generations
    #   sudo ${nixVersions.latest}/bin/nix-env --profile "$PROFILE" --rollback 3
    if [ $# -eq 0 ]; then
      sudo ${nixVersions.latest}/bin/nix-env --profile "$PROFILE" --rollback
    else
      sudo ${nixVersions.latest}/bin/nix-env --profile "$PROFILE" --rollback "$@"
    fi

    echo "Rolled back mgmt profile at $PROFILE"
  '';
}
