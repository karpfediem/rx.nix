{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.rx.mcl = {
    # Optional header imports at top of mgmt.mcl
    imports = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "datetime" "golang" ];
      description = "List of MCL imports to prepend into mgmt.mcl (e.g., \"datetime\").";
    };

    # Optional global let-bindings ($name = <expr>)
    vars = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { d = "datetime.now()"; };
      description = "Map of $var -> MCL expression to define as global signals.";
    };

    # Free-form MCL blocks to append (rendered verbatim)
    raw = mkOption {
      type = types.listOf types.lines;
      default = [ ];
      example = [
        ''
          file "/tmp/mgmt/datetime" {
            state   => $const.res.file.state.exists,
            content => golang.template("Hello! It is now: {{ datetime_print . }}\n", $d),
          }
        ''
      ];
      description = ''
        Raw MCL code prepended to the generated file. Rendered exactly as given.
        Use together with `rx.mcl.imports` and `rx.mcl.vars` to enable FRP examples.
      '';
    };
  };
}
