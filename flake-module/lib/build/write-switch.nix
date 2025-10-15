# Produce the switch-to-configuration script as a string.
# The script:
# - Updates /nix/var/nix/profiles/mgmt/current -> $GEN (atomic symlink flip)
# - Triggers systemd (system and user) to (re)start mgmt-apply
# - Falls back to running mgmt directly if the service isn't present
{ mgmtBin ? "mgmt" }:

''
#!/usr/bin/env bash
set -euo pipefail

GEN="''${1:-}"
if [ -z "$GEN" ]; then
  echo "usage: $0 /nix/store/...-rxnix-gen-<host>" >&2
  exit 1
fi

PROFILE="/nix/var/nix/profiles/mgmt/current"
sudo mkdir -p "$(dirname "$PROFILE")"
sudo ln -sfn "$GEN" "$PROFILE"

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
exec ${mgmtBin} run lang "$GEN/mgmt.mcl" --no-network
''

