{ lib }:
# Build a map of environment.etc KEY -> [ origin-file paths ... ],
# using options.environment.etc.definitionsWithLocations.
#
# Usage:
#   let etcOrigins = (import ./origins/etc-origins.nix { inherit lib; }) nixosCfg;
#   in etcOrigins."hosts"  # => [ "/nix/store/.../networking.nix" ... ]
#
# Notes:
# - We only need keys and their origin files. We don't evaluate content here.
# - For entries with `_type = "if" | "override"`, the 'value' we see is an
#   attrset whose keys we still collect. We don't descend into 'content'—the
#   existence of the key is sufficient for origin attribution.
nixosCfg:
let
  defs = (nixosCfg.options.environment.etc.definitionsWithLocations or []);
  # fold over the list of { file; value = { key = ...; ... } }
  addEntry = acc: entry:
    let
      file = entry.file;
      keys = builtins.attrNames (entry.value or {});
      addKey = acc2: k:
        acc2 // {
          ${k} = (acc2.${k} or []) ++ [ file ];
        };
    in
      lib.foldl' addKey acc keys;
in
  lib.foldl' addEntry {} defs
