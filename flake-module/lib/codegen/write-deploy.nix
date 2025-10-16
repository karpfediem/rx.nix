# write-deploy.nix
# Build the mgmt deploy directory from IR + MCL text.
{ lib }:
{ pkgs, name, filesIR, mclText }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "rxnix-deploy-${name}";
  version = "0.0.1";
  nativeBuildInputs = [ pkgs.jq ];
  preferLocalBuild = true;
  allowSubstitutes = false;
  buildCommand = ''
    set -euo pipefail
    mkdir -p "$out/deploy/files/nix"

    # 1) metadata.yaml — default entry point (main.mcl) and default files dir
    cat > "$out/deploy/metadata.yaml" <<'YAML'
# empty metadata is fine; main.mcl + files/ are the defaults
YAML

    # 2) main.mcl — the generated MCL program
    cat > "$out/deploy/main.mcl" <<'MCL'
import "deploy" # access stuff relating to the bundle of modules
import "golang" # contains a golang-style template(...) function

${mclText}
MCL

    # 3) manifest.json (optional debug artifact)
    cat > "$out/manifest.json" <<'JSON'
${builtins.toJSON filesIR}
JSON

    # 4) Materialize payload under deploy/files/nix/...
    jq -r '.files[] | @base64' "$out/manifest.json" | while read -r line; do
      obj=$(echo "$line" | base64 -d)
      absPath=$(echo "$obj" | jq -r '.path')
      content=$(echo "$obj" | jq -r '."__content" // empty')
      source=$(echo "$obj" | jq -r '."__source"  // empty')

      dest="$out/deploy/files/nix$absPath"
      mkdir -p "$(dirname "$dest")"
      if [ -n "$content" ]; then
        printf "%s" "$content" > "$dest"
      elif [ -n "$source" ]; then
        cp -L "$source" "$dest"
      else
        echo "missing content/source for $absPath" >&2
        exit 1
      fi
    done
  '';
}
