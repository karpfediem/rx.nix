{ profilePath ? "/nix/var/nix/profiles/mgmt/current"
, pkgs
, bash
, nixVersions
, systemdMinimal
, coreutils-full
}: pkgs.writeShellApplication {
  name = "switch-to-configuration";
  runtimeInputs = [
    bash
    nixVersions.latest
    systemdMinimal
    coreutils-full
  ];
  text = ''
    #!${bash}/bin/bash
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
      die "usage: $0 /nix/store/...-rx-gen-<host>"
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
      "$systemctl_bin" --system cat mgmt.service >/dev/null 2>&1
    }

    unit_exists_user() {
      local systemctl_bin="$1"
      "$systemctl_bin" --user cat mgmt.service >/dev/null 2>&1
    }

    restart_system_unit() {
      local systemctl_bin="$1"
      as_root "$systemctl_bin" --system daemon-reload || true
      as_root "$systemctl_bin" --system restart mgmt.service
    }

    restart_user_unit() {
      local systemctl_bin="$1"
      "$systemctl_bin" --user daemon-reload || true
      "$systemctl_bin" --user restart mgmt.service
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

    # Update the profile symlink
    if [ ! -e /nix/var/nix/db/db.sqlite ]; then
      # We are in likely booting right now in Stage 2
      log "nix DB not available yet; falling back to symlink update"
      as_root ln -sfn "$GEN" "$PROFILE"
      exit 0
    else
      NIX_ENV="${nixVersions.latest}/bin/nix-env"
      if [ -z "$NIX_ENV" ]; then
        die "result: FAIL (nix-env not found)"
      fi
      as_root "$NIX_ENV" --profile "$PROFILE" --set "$GEN"
    fi

    NEW_TARGET="$(resolve_link "$PROFILE")"
    if [ "$NEW_TARGET" != "$GEN" ]; then
      die "result: FAIL (profile update did not take effect; got: $(fmt_target "$NEW_TARGET"))"
    fi

    if [ ! -e /nix/var/nix/db/db.sqlite ]; then
      # Also gatekeep systemd while booting
      SYSTEMCTL="${systemdMinimal}/bin/systemctl"
      if [ -z "$SYSTEMCTL" ]; then
        log "result: UPDATED (no systemctl; restart skipped)"
        exit 0
      fi

      if unit_exists_system "$SYSTEMCTL"; then
        log "action: restart mgmt.service (system)"
        restart_system_unit "$SYSTEMCTL"
        log "result: UPDATED+RESTARTED (system)"
        exit 0
      fi

      if unit_exists_user "$SYSTEMCTL"; then
        log "action: restart mgmt.service (user)"
        restart_user_unit "$SYSTEMCTL"
        log "result: UPDATED+RESTARTED (user)"
        exit 0
      fi
    fi

    log "result: UPDATED (mgmt.service not found; restart skipped)"
    exit 0
  '';
}
