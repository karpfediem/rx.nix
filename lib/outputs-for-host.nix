{ lib, self, withSystem, allHosts }:

# Build {ir, gen, app} for exactly one host, resolving its own target system.
#
# Returns:
#   {
#     system = "x86_64-linux";
#     irDerivation = <drv>;
#     genDerivation = <drv>;
#     switchApp = { type = "app"; program = "..."; };
#   }
{ host }:
let
  inherit (lib) assertMsg;

  nixosCfg =
    assert assertMsg (builtins.hasAttr host allHosts)
      "rx: host '${host}' not found in provided allHosts";
    allHosts.${host};

  hostSystem =
    nixosCfg.pkgs.stdenv.hostPlatform.system
    or nixosCfg.pkgs.system
    or null;

  irForSystem = import ./ir/ir-for-system.nix {
    inherit lib self;
    # IMPORTANT: ir-for-system must not read self.nixosConfigurations internally;
    # it must use the passed allHosts. See next section.
    inherit allHosts;
  };

  buildGens = import ./build/build-gens.nix;

in
assert assertMsg (hostSystem != null)
  "rx: could not determine system for host '${host}'";
withSystem hostSystem ({ pkgs, ... }:
  let
    irByHost = irForSystem hostSystem;
    hostIR   = irByHost.${host} or { files = []; };

    irDrv = pkgs.writeText "rx-ir-${host}.json" (builtins.toJSON hostIR);

    gens   = buildGens { inherit pkgs; irByHost = { ${host} = hostIR; }; };
    genDrv = gens.${host};

    switchApp = {
      type = "app";
      program =
        (pkgs.writeShellApplication {
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
