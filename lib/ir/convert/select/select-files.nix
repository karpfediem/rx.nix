{ lib }:
# Select and synthesize the whitelisted /etc files + arbitrary rx.files to manage.
#
# Inputs:
#   nixosCfg   : evaluated nixos system for a host
#   policies   : (collect-policies.nix nixosCfg) result
#   etcOrigins : (etc-origins.nix nixosCfg) result
#
# Output:
#   Attrset: { "<abs path>" = { owner, group, mode, ensureDir, (text|source|generator+value)? ... }; ... }
#
args@{ nixosCfg, policies, etcOrigins }:
let
  inherit (lib) optionalAttrs removePrefix hasPrefix filterAttrs mapAttrs recursiveUpdate;

  cfg = nixosCfg.config;

  # hard gate: select nothing unless rx.enable
  rxEnabled = (cfg.rx.enable or false);

  # tiny helper to drop null values from an attrset
  dropNulls = attrs: filterAttrs (_: v: v != null) attrs;

  matchPolicy = import ../policy/match-policy.nix { inherit lib; };

  # Turn an /etc/<key> absolute path into the "key" part.
  etcKeyOfPath = p:
    if hasPrefix "/etc/" p then removePrefix "/etc/" p
    else throw "rx.include.files entry '${p}' must start with /etc/";

  # -------------------------- INCLUDE SETS -----------------------------------

  # 1) explicit includes (ABS /etc paths) from rx.include.files
  explicitIncludedAbs =
    if rxEnabled
    then filterAttrs (_p: v: (v.enable or false)) (policies.include.files or {})
    else {};

  # 2) policy-based includes: KEYS whose origins match include policies
  allEtcKeys = builtins.attrNames etcOrigins;
  policyIncludedKeys =
    if rxEnabled then
      lib.filter (k: matchPolicy {
        byPolicy    = policies.include.byPolicy or {};
        kind        = "files";
        originPaths = etcOrigins.${k} or [];
      }) allEtcKeys
    else
      [];

  includedAbsFromPolicy =
    lib.listToAttrs (map (k: { name = "/etc/${k}"; value = true; }) policyIncludedKeys);

  # 3) treat rx.files entries as explicit includes too (free paths)
  rxFilesIncludedAbs =
    if rxEnabled
    then mapAttrs (_p: _v: true) (cfg.rx.files or {})
    else {};

  # 4) combined includes (ABS path -> true)
  includedAbs =
    mapAttrs (_: _v: true) (explicitIncludedAbs // includedAbsFromPolicy // rxFilesIncludedAbs);

  # -------------------------- EXCLUDES ---------------------------------------

  # by-policy exclude (only meaningful for /etc paths that have origins)
  isExcludedByPolicy = absPath:
    if hasPrefix "/etc/" absPath then
      let key = etcKeyOfPath absPath;
      in matchPolicy {
        byPolicy    = policies.exclude.byPolicy or {};
        kind        = "files";
        originPaths = etcOrigins.${key} or [];
      }
    else
      false;

  includedAbsFiltered =
    filterAttrs (absPath: _:
      rxEnabled
      && !(policies.exclude.files.${absPath} or false)
      && !isExcludedByPolicy absPath
    ) includedAbs;

  # Partition into /etc-bound vs free-path entries.
  etcAbs   = filterAttrs (p: _: hasPrefix "/etc/" p) includedAbsFiltered;
  freeAbs  = filterAttrs (p: _: !hasPrefix "/etc/" p) includedAbsFiltered;

  # ---------------------- RECORD SYNTHESIS -----------------------------------

  # A) /etc-bound record (defaults from environment.etc.<key>)
  mkEtcRecord = absPath:
    let
      key = etcKeyOfPath absPath;
      e   = (cfg.environment.etc.${key} or null);  # touch env.etc only after selection

      # Defaults derived from environment.etc.<key> (if present).
      # Parenthesize each term in merges to avoid precedence pitfalls.
      defaults =
        (if e != null && e ? user  then { owner = e.user; }  else {})
        // (if e == null || (! e ? user) then { owner = "root"; } else {})
        // (if e != null && e ? group then { group = e.group; } else {})
        // (if e == null || (! e ? group) then { group = "root"; } else {})
        // (if e != null && e ? mode  then { mode  = e.mode;  } else {})
        // (if e == null || (! e ? mode)  then { mode  = "0644"; } else {})
        // (if e != null && e ? text && e.text != null
            then { text = e.text; }
            else if e != null && (e ? source || e ? target)
              then { source = (e.source or e.target); }
              else {})
        // { ensureDir = true; };

      # Include overlay for this path: remove 'enable' and ALL nulls so we don't clobber defaults.
      incUser =
        let raw = policies.include.files.${absPath} or {};
        in dropNulls (lib.removeAttrs raw [ "enable" ]);

      # Optional rx.files override for this path: drop nulls too.
      rxOverride =
        let raw = cfg.rx.files.${absPath} or {};
        in dropNulls raw;

      merged  = recursiveUpdate defaults incUser;
      merged' = recursiveUpdate merged   rxOverride;
    in
      merged';

  # B) free-path record (only from rx.files; no environment.etc defaults)
  mkFreeRecord = absPath:
    let
      rxOverride =
        let raw = cfg.rx.files.${absPath} or {};
        in dropNulls raw;

      defaults = {
        owner = "root";
        group = "root";
        mode  = "0644";
        ensureDir = true;
      };

      merged' = recursiveUpdate defaults rxOverride;
    in
      merged';

  # Build both maps and unify.
  etcRecords  = mapAttrs (p: _v: mkEtcRecord p) etcAbs;
  freeRecords = mapAttrs (p: _v: mkFreeRecord p) freeAbs;

  filesAttr = etcRecords // freeRecords;

in
  filesAttr
