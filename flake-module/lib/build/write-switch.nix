# Produce the switch-to-configuration script as a string.
# Switches the "mgmt" profile to the given generation path using nix-env --set,
# then tries to bounce mgmt-apply via systemd (system or user); else runs mgmt inline.
{ mgmtBin ? "mgmt"
, profilePath ? "/nix/var/nix/profiles/mgmt/current"
}:

''
  #!/usr/bin/env bash
  set -euo pipefail

  GEN="''${1:-}"
  if [ -z "$GEN" ]; then
    echo "usage: $0 /nix/store/...-rxnix-gen-<host>" >&2
    exit 1
  fi

  PROFILE="${profilePath}"

  # Ensure parent directory exists (matches common macOS/Linux issue).
  if [ ! -e "$(dirname "$PROFILE")" ]; then
    echo "Creating profile parent dir: $(dirname "$PROFILE") (sudo)"
    sudo mkdir -p "$(dirname "$PROFILE")"
  fi

  # Atomically set the profile to this generation, like flakey-profile does.
  # This updates .../mgmt/current and creates a new .../mgmt/current-<n> generation.
  sudo nix-env \
    --profile "$PROFILE" \
    --set "$GEN"

  # Prefer a systemd service if available; otherwise run mgmt inline.
  restart_unit() {
    local scope="$1" # "system" or "user"
    if command -v systemctl >/dev/null 2>&1; then
      if systemctl --"$scope" list-unit-files | grep -q '^mgmt-apply\.service'; then
        systemctl --"$scope" daemon-reload || true
        systemctl --"$scope" try-restart mgmt-apply.service || systemctl --"$scope" restart mgmt-apply.service || true
        return 0
      fi
    fi
    return 1
  }

  if restart_unit system; then
    echo "Switched mgmt profile (system scope): $GEN"
    exit 0
  fi

  if restart_unit user; then
    echo "Switched mgmt profile (user scope): $GEN"
    exit 0
  fi

  # Fallback: run mgmt directly with absolute MCL path
  echo "No mgmt-apply.service found; running mgmt directly..." >&2
  set -x
  exec ${mgmtBin} run lang "$GEN/deploy/metadata.yaml" --no-network
''
