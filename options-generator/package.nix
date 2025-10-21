{ lib, buildGoModule }:
buildGoModule {
  pname = "options-generator";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  vendorHash = "sha256-SlG9Qd7NGlCJKgDY0+U8muuuGEQ7KFMQZdeb5gl+Xts=";
}
