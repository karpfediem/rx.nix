{ lib, self, withSystem }:

# Build {ir, gen, app} for exactly one host, resolving its own target system.
#
# Usage:
#   (import ./lib/gen-for-host.nix { inherit lib self withSystem; }) {
#     host   = "demo";
#   }
#
# Returns:
#   {
#     system = "x86_64-linux";          # host's target system
#     irDerivation = <text drv>;        # pkgs.writeText ... rx-ir-<host>.json
#     genDerivation = <drv>;            # rxnix-gen-<host>-<ver>
#     switchApp = { type = "app"; program = "/nix/store/.../bin/rx-switch-<host>"; };
#   }

{ host }:
let
  inherit (lib) assertMsg mapAttrs;

  # Pull the configured host from consumer flake
  allHosts = (self.nixosConfigurations or {});
  nixosCfg =
    assert assertMsg (allHosts ? ${host})
      "rx: host '${host}' not found in self.nixosConfigurations";
    allHosts.${host};

  # Resolve the host's target system as defined by its pkgs
  hostSystem =
    nixosCfg.pkgs.stdenv.hostPlatform.system
    or nixosCfg.pkgs.system
    or null;

  # Bring in the same helpers you already use
  irForSystem = import ./ir-for-system.nix { inherit lib self; };
  buildGens   = import ./build-gens.nix    { inherit lib; };

in
withSystem hostSystem ({ pkgs, ... }:
  let
    # Compute IR only for this host (reuse the system-wide function, then pick one)
    irByHost  = irForSystem hostSystem;
    hostIR    = irByHost.${host} or { files = []; };

    irDrv     = pkgs.writeText "rx-ir-${host}.json" (builtins.toJSON hostIR);

    # Build a single-host generation by wrapping in a singleton attrset
    gens      = buildGens pkgs { ${host} = hostIR; };
    genDrv    = gens.${host};

    switchApp = {
      type = "app";
      program = (pkgs.writeShellApplication {
        name = "rx-switch-${host}";
        text = ''
          set -euo pipefail
          GEN="${genDrv}"
          exec "$GEN/switch-to-configuration" "$GEN"
        '';
      }).outPath + "/bin/rx-switch-${host}";
    };
  in
  {
    system = hostSystem;
    irDerivation  = irDrv;
    genDerivation = genDrv;
    switchApp     = switchApp;
  }
)
