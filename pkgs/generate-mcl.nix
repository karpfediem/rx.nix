{ runCommand, codegen, irJson }:
# irJson is a path or derivation that contains the evaluated IR JSON

runCommand "rxnix-ir-to-mcl"
  { nativeBuildInputs = [ codegen ]; }
  ''
    set -euo pipefail
    mkdir -p "$out"
    # Writes one <host>.mcl per host into $out
    ${codegen}/bin/mcl \
      -in ${irJson} \
      -out "$out"

    # optional sanity check: there should be at least one .mcl
    test -n "$(echo "$out"/*.mcl 2>/dev/null || true)"
  ''
