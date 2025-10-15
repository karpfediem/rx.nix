{ lib }:
# discoverHosts :: self -> system -> { hostName = nixosCfg; ... }
self: system:
let
  all = (self.nixosConfigurations or {});
in
lib.filterAttrs (_: cfg:
  let
    hostSys =
      cfg.pkgs.stdenv.hostPlatform.system
      or cfg.pkgs.system
      or null;
  in hostSys == system
) all
