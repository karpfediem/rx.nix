{ lib }:
pkgs: irByHost:
let
  mclFromIr = import ./codegen/mcl-from-ir.nix { inherit lib; };
  writeSwitch = import ./build/write-switch.nix { mgmtBin = "${pkgs.mgmt}/bin/mgmt"; };
in
lib.mapAttrs (_host: filesIR:
  pkgs.stdenvNoCC.mkDerivation {
    pname = "rxnix-gen-${_host}";
    version = "0.0.1";
    nativeBuildInputs = with pkgs; [ jq coreutils gnused ];
    preferLocalBuild = true;
    allowSubstitutes = false;

    buildCommand = ''
      set -euo pipefail
      mkdir -p "$out" "$out/payload"

      # 1) Write manifest.json
      cat > "$out/manifest.json" <<'JSON'
${builtins.toJSON filesIR}
JSON

      # 2) Materialize payload flat rootfs (from __content or __source)
      jq -r '.files[] | @base64' "$out/manifest.json" | while read -r line; do
        obj=$(echo "$line" | base64 -d)
        srcRel=$(echo "$obj" | jq -r '.src')
        content=$(echo "$obj" | jq -r '."__content" // empty')
        source=$(echo "$obj" | jq -r '."__source"  // empty')

        dest="$out/payload/''${srcRel}"
        mkdir -p "$(dirname "$dest")"

        if [ -n "$content" ]; then
          printf "%s" "$content" > "$dest"
        elif [ -n "$source" ]; then
          cp -L "$source" "$dest"
        else
          echo "missing content/source for: $srcRel" >&2
          exit 1
        fi
      done

      # 3) Generate mgmt.mcl from IR
      cat > "$out/mgmt.mcl" <<'MCL'
${mclFromIr filesIR}
MCL

      # 4) Rewrite payload path to true outPath inside nix store
      sed -i "s#source  => \"payload/#source  => \"$out/payload/#g" "$out/mgmt.mcl"

      # 5) Switcher
      cat > "$out/switch-to-configuration" <<'SH'
${writeSwitch}
SH
      chmod +x "$out/switch-to-configuration"
    '';
  }
) irByHost
