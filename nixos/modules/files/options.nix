{ lib
, withEnable ? false          # add an `enable` switch
, nullableFields ? false      # true for include.files (we’ll back-fill from env.etc)
}:

let
  inherit (lib) mkOption mkEnableOption types;

  strOrNull = types.nullOr types.str;
  pathOrNull = types.nullOr types.path;

  contentOptions =
    if nullableFields then {
      text      = mkOption { type = strOrNull;  default = null; };
      source    = mkOption { type = pathOrNull; default = null; };
      generator = mkOption { type = types.nullOr types.anything; default = null; };
      value     = mkOption { type = types.nullOr types.anything; default = null; };
    } else {
      text      = mkOption { type = types.nullOr types.str;  default = null; };
      source    = mkOption { type = types.nullOr types.path; default = null; };
      generator = mkOption { type = types.nullOr types.anything; default = null; };
      value     = mkOption { type = types.nullOr types.anything; default = null; };
    };

  ownerGroupMode =
    if nullableFields then {
      owner     = mkOption { type = types.nullOr types.str;  default = null; };
      group     = mkOption { type = types.nullOr types.str;  default = null; };
      mode      = mkOption { type = types.nullOr types.str;  default = null; };
      ensureDir = mkOption { type = types.nullOr types.bool; default = null; };
    } else {
      owner     = mkOption { type = types.str;  default = "root"; };
      group     = mkOption { type = types.str;  default = "root"; };
      mode      = mkOption { type = types.str;  default = "0644"; };
      ensureDir = mkOption { type = types.bool; default = true; };
    };
in
{
  options =
    (lib.optionalAttrs withEnable {
      enable = mkEnableOption "manage this resource via rx";
    })
    // contentOptions
    // ownerGroupMode;
}
