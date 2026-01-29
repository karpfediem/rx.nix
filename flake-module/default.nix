# The importApply argument. Use this to reference things defined locally,
# as opposed to the flake where this is imported.
localFlake:

{ lib, config, self, withSystem, ... }:
let
  inherit (lib) mapAttrs;

  allHosts = self.nixosConfigurations or {};

  genForHost = import ../lib/outputs-for-host.nix {
    inherit lib self withSystem allHosts;
  };

  irForSystem = import ../lib/ir/ir-for-system.nix {
    inherit lib self allHosts;
  };

  buildGens = import ../lib/build/build-per-host-deploys.nix;
in
{
  perSystem = { pkgs, system, ... }:
  let
    irByHost = irForSystem system;
    gens     = buildGens { inherit irByHost pkgs; };

    selectedPaths =
      lib.mapAttrs (_host: ir: map (f: f.path) (ir.files or [])) irByHost;

    hostsForSystem =
      lib.filterAttrs (_: nixosCfg:
        let
          hostSys =
            nixosCfg.pkgs.stdenv.hostPlatform.system
              or nixosCfg.pkgs.system
              or null;
        in
        hostSys == system
      ) allHosts;

    rxView = lib.mapAttrs (_: nixosCfg: {
      enable        = nixosCfg.config.rx.enable or false;
      include_files = nixosCfg.config.rx.include.files or {};
      exclude_files = nixosCfg.config.rx.exclude.files or {};
    }) hostsForSystem;
  in
  {
    packages.rx-selected = pkgs.writeText "rx-selected.json" (builtins.toJSON selectedPaths);
    packages.rx-rxview   = pkgs.writeText "rx-rxview.json"   (builtins.toJSON rxView);
    packages.rx-ir       = pkgs.writeText "rx-ir.json"       (builtins.toJSON irByHost);

    apps = lib.mapAttrs (host: gen: {
      type = "app";
      program = (pkgs.writeShellApplication {
        name = "rx-switch-${host}";
        text = ''
          set -euo pipefail
          GEN="${gen}"
          exec "$GEN/switch-to-configuration" "$GEN"
        '';
      }).outPath + "/bin/rx-switch-${host}";
    }) gens;
  };

  flake.rxSystems =
    let systems = config.systems or [ "x86_64-linux" ];
    in builtins.listToAttrs (map
      (sys: {
        name = sys;
        value = localFlake.withSystem sys ({ pkgs, ... }:
          let irByHost = (import ../lib/ir/ir-for-system.nix {
                inherit lib self allHosts;
              }) sys;
          in buildGens { inherit pkgs irByHost; }
        );
      })
      systems);

  # A JSON IR per host, accessible like:  nix build .#rxIR.demo
  flake.rxIR =
    mapAttrs (host: _cfg:
      let r = genForHost { inherit host; };
      in r.irDerivation
    ) allHosts;

  # A generation per host, accessible like:  nix build .#rxHosts.demo
  flake.rxHosts =
    mapAttrs (host: _cfg:
      let r = genForHost { inherit host; };
      in r.genDerivation
    ) allHosts;

  # A switch app per host, accessible like:  nix run .#rxSwitch.demo
  flake.apps.rxSwitch =
    mapAttrs (host: _cfg:
      let r = genForHost { inherit host; };
      in r.switchApp
    ) allHosts;
}
