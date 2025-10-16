# Pure MCL generator from our IR (files-only PoC).
# Usage: (import ./codegen/mcl-from-ir.nix { inherit lib; })(filesIR)
{ lib }:
let
  esc = s: lib.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] (toString s);

  renderFile = import ./file.nix { inherit esc; };

  renderImports = imports:
    lib.concatStringsSep "\n\n" (map (m: ''import "${esc m}"'') imports);

  renderVars = vars:
    let names = builtins.attrNames vars;
    in lib.concatStringsSep "\n\n" (map
      (n: ''''$${n} = ${(vars.${n})}'')
      names);

  renderRaw = raws:
    lib.concatStringsSep "\n\n" raws;
in
filesIR:
let
  prelude = filesIR.mclPrelude or { };
  userImports = renderImports prelude.imports;
  userVars = renderVars prelude.vars;
  userRaw = renderRaw prelude.raw;

  body =
    lib.concatMapStrings (f: renderFile f + "\n")
      (filesIR.files or [ ]);

in
lib.concatStringsSep "\n\n" ([
  userImports
  userVars
  userRaw
  body
])
