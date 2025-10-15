{ lib, ... }:
let
  inherit (lib) mkOption types;
  fileRes = import ./options.nix {
    inherit lib;
    withEnable = false;
    nullableFields = false; # concrete defaults (root/0644/true)
  };
in
{
  options.rx.files = mkOption {
    # Each attr (absolute /etc path) is a submodule with the file options above
    type = types.attrsOf (types.submodule (_: fileRes));
    default = {};
    description = "Extra rx-managed files (/etc paths). Merged last as overrides.";
  };
}
