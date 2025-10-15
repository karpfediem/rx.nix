{ lib }:
nixosCfg:
let
  cfg = nixosCfg.config.rx or {};

  # safely extract a boolean nested at *.enable; otherwise false
  getEnabled = x:
    if x == null then false
    else if builtins.isAttrs x && x ? enable then (x.enable or false)
    else if builtins.isBool x then x
    else false;

  normByPolicy = ap:
    lib.mapAttrs (_k: v: {
      files    = getEnabled (v.files    or null);
      systemd  = getEnabled (v.systemd  or null);
      packages = getEnabled (v.packages or null);
    }) ap;

  # normalize explicit include maps: ensure 'enable' attr exists (false default)
  normExplicitInc = m:
    lib.mapAttrs (_: v:
      if builtins.isAttrs v then v // { enable = (v.enable or false); } else { enable = !!v; }
    ) m;

  # normalize explicit excludes to boolean
  normExplicitExc = m: lib.mapAttrs (_: v: !!v) m;

in
{
  include = {
    byPolicy = normByPolicy (cfg.include.by-policy or {});
    files    = normExplicitInc (cfg.include.files or {});
    systemd  = normExplicitInc (cfg.include.systemd or {});
    packages = normExplicitInc (cfg.include.packages or {});
  };

  exclude = {
    byPolicy = normByPolicy (cfg.exclude.by-policy or {});
    files    = normExplicitExc (cfg.exclude.files or {});
    systemd  = normExplicitExc (cfg.exclude.systemd or {});
    packages = normExplicitExc (cfg.exclude.packages or {});
  };
}
