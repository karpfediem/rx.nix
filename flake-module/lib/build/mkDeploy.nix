# Build deploy dir from IR; the codegen decides shape and filenames.
{ stdenvNoCC, codegen }:
{ name, ir }:

stdenvNoCC.mkDerivation {
  pname = "rxnix-deploy-${name}";
  version = "0.0.4";
  nativeBuildInputs = [ codegen ];
  preferLocalBuild = true;
  allowSubstitutes = false;

  buildCommand = ''
    set -euo pipefail
    mkdir -p "$out/deploy"
    # Let codegen produce <host>.mcl files into deploy/
    ${codegen}/bin/mcl -in ${ir} -out "$out/deploy"
    # Optional: if you still want a metadata stub
    cat > "$out/deploy/metadata.yaml" <<'YAML'
# empty metadata is fine; main.mcl + files/ are the defaults
YAML
  '';
}
