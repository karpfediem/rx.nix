{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
  bool = types.bool;

  # reusable fragment for include.files: has `enable` and nullable fields
  includeFileRes = import ./files/options.nix {
    inherit lib;
    withEnable = true;
    nullableFields = true;  # we back-fill from environment.etc at selection time
  };

  mkEnabledSub = desc: types.submodule (_: {
    options.enable = mkEnableOption desc;
  });
in
{
  options.rx = {
    enable = mkEnableOption "rx projection for this host";

    include.by-policy = mkOption {
      type = types.attrsOf (types.submodule (_: {
        options = {
          files    = mkOption { type = mkEnabledSub "by-policy (files)";    default = {}; };
          systemd  = mkOption { type = mkEnabledSub "by-policy (systemd)";  default = {}; };
          packages = mkOption { type = mkEnabledSub "by-policy (packages)"; default = {}; };
        };
      }));
      default = {};
    };

    exclude.by-policy = mkOption {
      type = types.attrsOf (types.submodule (_: {
        options = {
          files    = mkOption { type = mkEnabledSub "by-policy exclude (files)";    default = {}; };
          systemd  = mkOption { type = mkEnabledSub "by-policy exclude (systemd)";  default = {}; };
          packages = mkOption { type = mkEnabledSub "by-policy exclude (packages)"; default = {}; };
        };
      }));
      default = {};
    };

    include.files = mkOption {
      type = types.attrsOf (types.submodule (_: includeFileRes));
      default = {};
      description = "Explicit /etc files. If only `enable = true;` is set, defaults are taken from environment.etc.";
    };

    exclude.files = mkOption {
      type = types.attrsOf bool;
      default = {};
    };
  };
}
