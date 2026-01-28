# Build deploy dir from IR; the codegen decides shape and filenames.
{ deployName, ir }:
{ stdenvNoCC, callPackage, rx-codegen ? callPackage ../../pkgs/codegen.nix {} }:

stdenvNoCC.mkDerivation {
  pname = "rxnix-deploy-${deployName}";
  version = "0.0.4";
  nativeBuildInputs = [ rx-codegen ];
  preferLocalBuild = true;
  allowSubstitutes = false;

  buildCommand = ''
    set -euo pipefail
    mkdir -p "$out/deploy"
    cat > "ir.json" <<'JSON'
${builtins.toJSON ir}
JSON
    # Let codegen produce <host>.mcl files into deploy/
    ${rx-codegen}/bin/mcl -in ir.json -out "$out/deploy"
    # Optional: if you still want a metadata stub
    cat > "$out/deploy/metadata.yaml" <<'YAML'
# empty metadata is fine; main.mcl + files/ are the defaults
YAML
  '';
}
