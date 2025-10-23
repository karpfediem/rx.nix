{ fetchFromGitHub, runCommand, codegen }:
let
  mgmtSrc = fetchFromGitHub {
    owner = "purpleidea";
    repo = "mgmt";
    rev = "8293d37f4500dfe4d530e4aa7dbe4ab8be352dc1";
    hash = "sha256-71G71GO2cGavDNKc+3lEQmFmTtX2skIjqWZKVl7o4kE=";
  };
in
runCommand "rx-nixos-options" { nativeBuildInputs = [ codegen ]; } ''
  set -euo pipefail
  mkdir -p "$out"
  export CGO_ENABLED=0 GOOS=linux GOARCH=amd64
  ${codegen}/bin/nixos \
    -mgmt-dir ${mgmtSrc} \
    -out-dir "$out"
  test -f "$out/default.nix"
''
