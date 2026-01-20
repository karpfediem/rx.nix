{ lib, self, allHosts }:

# Build the intermediate representation (IR) map for a single CPU system:
#   system -> { host = { files = [ ... ] ; } ; ... }

let
  inherit (lib) mapAttrs filterAttrs;

  discoverHosts = system: filterAttrs
      (_: cfg:
        let
          hostSys =
            cfg.pkgs.stdenv.hostPlatform.system
              or cfg.pkgs.system
              or null;
        in
        hostSys == system
      )
      allHosts;

in
system:
let
  hosts = discoverHosts system;
  inherit (lib.lists) unique;
in
mapAttrs
  (_host: nixosCfg:
  let
      cfg = nixosCfg.config;
      mclImports = (cfg.rx.mcl.imports or []);
      mclVars    = (cfg.rx.mcl.vars    or {});
      mclRaw     = (cfg.rx.mcl.raw     or []);
      rxRes      = (cfg.rx.res         or {});
  in
    {
      imports = unique (["deploy"] ++ mclImports);
      vars    = mclVars;
      raw     = mclRaw;
      res     = rxRes;
    }
  )
  hosts
