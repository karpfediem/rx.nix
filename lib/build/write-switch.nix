{ profilePath ? "/nix/var/nix/profiles/mgmt/current" }:
''
  #!/usr/bin/env bash
  set -euo pipefail

  # ----------------------------------------------------------------------------
  # Logging helpers (stderr) — no timestamps, aligned old/new
  # ----------------------------------------------------------------------------
  log() { printf 'rx.mgmt.switch %s\n' "$*" >&2; }
  die() { log "ERROR: $*"; exit 1; }

  short_store() {
    # /nix/store/<hash>-<name> -> <name> (fallback: basename)
    local p="$1"
    if [ -z "$p" ]; then
      printf '%s' ""
      return 0
    fi
    local b
    b="$(basename "$p" 2>/dev/null || true)"
    if [[ "$b" == *-* ]]; then
      printf '%s' "''${b#*-}"
    else
      printf '%s' "$b"
    fi
  }

  fmt_target() {
    # Print a compact "<name> (<fullpath>)" line, or "<none>"
    local p="$1"
    if [ -z "$p" ]; then
      printf '%s' "<none>"
      return 0
    fi
    printf '%s (%s)' "$(short_store "$p")" "$p"
  }

  # ----------------------------------------------------------------------------
  # Args & basic validation
  # ----------------------------------------------------------------------------
  GEN="''${1:-}"
  if [ -z "$GEN" ]; then
    die "usage: $0 /nix/store/...-rxnix-gen-<host>"
  fi
  if [[ "$GEN" != /* ]]; then
    die "invalid GEN (must be absolute): $GEN"
  fi

  PROFILE="${profilePath}"

  # ----------------------------------------------------------------------------
  # Privilege helpers
  # ----------------------------------------------------------------------------
  as_root() {
    if [ "''${EUID:-$(id -u)}" -eq 0 ]; then
      "$@"
    else
      sudo "$@"
    fi
  }

  mode() {
    if [ "''${EUID:-$(id -u)}" -eq 0 ]; then
      printf '%s' "root"
    else
      printf '%s' "sudo"
    fi
  }

  # ----------------------------------------------------------------------------
  # Tool selection (activation-safe)
  # ----------------------------------------------------------------------------
  pick_systemctl() {
    if [ -x /run/current-system/sw/bin/systemctl ]; then
      printf '%s' "/run/current-system/sw/bin/systemctl"
      return 0
    fi
    if command -v systemctl >/dev/null 2>&1; then
      command -v systemctl
      return 0
    fi
    printf '%s' ""
  }

  pick_nix_env() {
    if [ -x /run/current-system/sw/bin/nix-env ]; then
      printf '%s' "/run/current-system/sw/bin/nix-env"
      return 0
    fi
    if command -v nix-env >/dev/null 2>&1; then
      command -v nix-env
      return 0
    fi
    printf '%s' ""
  }

  resolve_link() {
    local p="$1"
    if [ -e "$p" ]; then
      readlink -f "$p" 2>/dev/null || true
    else
      printf '%s' ""
    fi
  }

  unit_exists_system() {
    local systemctl_bin="$1"
    "$systemctl_bin" --system cat mgmt-apply.service >/dev/null 2>&1
  }

  unit_exists_user() {
    local systemctl_bin="$1"
    "$systemctl_bin" --user cat mgmt-apply.service >/dev/null 2>&1
  }

  restart_system_unit() {
    local systemctl_bin="$1"
    as_root "$systemctl_bin" --system daemon-reload || true
    as_root "$systemctl_bin" --system restart mgmt-apply.service
  }

  restart_user_unit() {
    local systemctl_bin="$1"
    "$systemctl_bin" --user daemon-reload || true
    "$systemctl_bin" --user restart mgmt-apply.service
  }

  # ----------------------------------------------------------------------------
  # Main flow
  # ----------------------------------------------------------------------------
  CURRENT_TARGET="$(resolve_link "$PROFILE")"

  log "start (mode=$(mode))"
  log "  profile: ''${PROFILE}"
  log "  current: $(fmt_target "$CURRENT_TARGET")"
  log "  new:     $(fmt_target "$GEN")"

  if [ "$CURRENT_TARGET" = "$GEN" ]; then
    log "result: SKIP (profile unchanged)"
    exit 0
  fi

  as_root mkdir -p "$(dirname "$PROFILE")"

  NIX_ENV="$(pick_nix_env)"
  if [ -z "$NIX_ENV" ]; then
    die "result: FAIL (nix-env not found)"
  fi

  log "action: set profile"
  as_root "$NIX_ENV" --profile "$PROFILE" --set "$GEN"

  NEW_TARGET="$(resolve_link "$PROFILE")"
  if [ "$NEW_TARGET" != "$GEN" ]; then
    die "result: FAIL (profile update did not take effect; got: $(fmt_target "$NEW_TARGET"))"
  fi

  SYSTEMCTL="$(pick_systemctl)"
  if [ -z "$SYSTEMCTL" ]; then
    log "result: UPDATED (no systemctl; restart skipped)"
    exit 0
  fi

  if unit_exists_system "$SYSTEMCTL"; then
    log "action: restart mgmt-apply.service (system)"
    restart_system_unit "$SYSTEMCTL"
    log "result: UPDATED+RESTARTED (system)"
    exit 0
  fi

  if unit_exists_user "$SYSTEMCTL"; then
    log "action: restart mgmt-apply.service (user)"
    restart_user_unit "$SYSTEMCTL"
    log "result: UPDATED+RESTARTED (user)"
    exit 0
  fi

  log "result: UPDATED (mgmt-apply.service not found; restart skipped)"
  exit 0
''
