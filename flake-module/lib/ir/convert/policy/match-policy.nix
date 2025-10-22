{ lib }:
# Decide whether a resource with given originPaths matches a set of "by-policy"
# rules for a given kind ("files" | "systemd" | "packages").
#
# Usage:
#   let matchPolicy = import ./policy/match-policy.nix { inherit lib; };
#   in matchPolicy { byPolicy = policies.include.byPolicy; kind = "files"; originPaths = [ "/nix/store/.../filesystems.nix" ]; }
#      -> true / false
{ byPolicy ? {}, kind, originPaths ? [] }:
let
  keys = builtins.attrNames byPolicy;

  anyOriginMatches = polSubstr:
    let
      enabled = (byPolicy.${polSubstr}.${kind} or false);
    in
      enabled && lib.any (p: lib.hasInfix polSubstr p) originPaths;
in
  lib.any anyOriginMatches keys
