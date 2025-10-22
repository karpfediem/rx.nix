# The importApply argument. Use this to reference things defined locally,
# as opposed to the flake where this is imported.
localFlake:

{ lib, config, self, withSystem, ... }:
let
  inherit (lib) mapAttrs;

  genForHost = import ./lib/gen-for-host.nix { inherit lib self withSystem; };

  allHosts = (self.nixosConfigurations or {});
  # Use the consumer's `self` inside ir-for-system
  irForSystem = import ./lib/ir/ir-for-system.nix { inherit lib self; };
  buildGens   = import ./lib/build/build-gens.nix    { inherit lib; };
in
{
  # ------------------------- perSystem outputs -------------------------------
  perSystem = { pkgs, system, ... }:
  let
    irByHost = irForSystem system;
    gens     = buildGens pkgs irByHost;

    # NEW: expose selected paths and raw rx view per host
    selectedPaths =
      lib.mapAttrs (_host: ir: map (f: f.path) (ir.files or [])) irByHost;

    # pull the evaluated nixosConfigurations for this system so we can inspect rx.*
    hosts =
      let all = (self.nixosConfigurations or {});
      in lib.filterAttrs (_: cfg:
        let sys = (cfg.pkgs.stdenv.hostPlatform.system or cfg.pkgs.system or null);
        in sys == system
      ) all;

    rxView = lib.mapAttrs (_: nixosCfg: {
      enable = nixosCfg.config.rx.enable or false;
      include_files = nixosCfg.config.rx.include.files or {};
      exclude_files = nixosCfg.config.rx.exclude.files or {};
    }) hosts;
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

  # ------------------------- top-level aggregation ---------------------------

  # flake.rxSystems.${system}.${host} = derivation
  flake.rxSystems =
    let systems = config.systems or [ "x86_64-linux" ];
    in builtins.listToAttrs (map
      (sys: {
        name = sys;
        value = localFlake.withSystem sys ({ pkgs, ... }:
          let irByHost' = (import ./lib/ir-for-system.nix { inherit lib self; }) sys;
          in buildGens pkgs irByHost'
        );
      })
      systems);

  # A JSON IR per host, accessible like:  nix build .#rxIrForHost.demo
  flake.rxIrForHost =
    mapAttrs (host: _cfg:
      let r = genForHost { inherit host; };
      in r.irDerivation
    ) allHosts;

  # A generation per host, accessible like:  nix build .#rxGenForHost.demo
  flake.rxGenForHost =
    mapAttrs (host: _cfg:
      let r = genForHost { inherit host; };
      in r.genDerivation
    ) allHosts;

  # A switch app per host, accessible like:  nix run .#rxSwitchForHost.demo
  flake.apps.rxSwitchForHost =
    mapAttrs (host: _cfg:
      let r = genForHost { inherit host; };
      in r.switchApp
    ) allHosts;
}
