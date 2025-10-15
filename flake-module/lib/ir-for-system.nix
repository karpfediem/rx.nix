{ lib, self }:

# Build the intermediate representation (IR) map for a single CPU system:
#   system -> { host = { files = [ ... ] ; } ; ... }
#
# IMPORTANT:
# - Discovery reads the *consumer* flake's nixosConfigurations via `self`.
# - We select /etc files *only* via the whitelist selector (select-files.nix).
# - We never traverse all of config.environment.etc; we touch a key only
#   after it has been selected, so unselected items (e.g. binfmt) are never evaluated.

let
  inherit (lib) mapAttrs filterAttrs;

  # Selection pipeline pieces
  collectPolicies = import ./policy/collect-policies.nix { inherit lib; };
  etcOriginsOf    = import ./origins/etc-origins.nix     { inherit lib; };
  selectFiles     = import ./select/select-files.nix     { inherit lib; };

  # IR projector (validates “exactly one of text | source | (generator+value)”)
  projectIR = import ./project-ir.nix { inherit lib; };

  discoverHosts = system:
    let all = (self.nixosConfigurations or {});
    in filterAttrs (_: cfg:
      let hostSys =
        cfg.pkgs.stdenv.hostPlatform.system
        or cfg.pkgs.system
        or null;
      in hostSys == system
    ) all;

in
system:
let
  hosts = discoverHosts system;
in
mapAttrs (_host: nixosCfg:
  let
    policies  = collectPolicies nixosCfg;
    etcOrigin = etcOriginsOf nixosCfg;
    filesAttr = selectFiles { inherit nixosCfg policies; etcOrigins = etcOrigin; };
  in
    projectIR filesAttr
) hosts
