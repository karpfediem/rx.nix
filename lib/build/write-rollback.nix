# Generates a rollback script for the mgmt profile.
{ profilePath ? "/nix/var/nix/profiles/mgmt/current" }:

''
  #!/usr/bin/env bash
  set -euo pipefail

  PROFILE="${profilePath}"

  # Roll back to the previous generation of the mgmt profile.
  # If you want to roll back multiple steps, pass a generation number:
  #   nix-env --profile "$PROFILE" --list-generations
  #   sudo nix-env --profile "$PROFILE" --rollback 3
  if [ $# -eq 0 ]; then
    sudo nix-env --profile "$PROFILE" --rollback
  else
    sudo nix-env --profile "$PROFILE" --rollback "$@"
  fi

  echo "Rolled back mgmt profile at $PROFILE"
''
