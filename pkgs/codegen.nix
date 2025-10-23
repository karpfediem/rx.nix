{ lib, buildGoModule }:
buildGoModule {
  pname = "rx-codegen";
  version = "0.2.0";
  src = lib.cleanSource ../codegen;
  subPackages = [
    "cmd/nixos"
    "cmd/mcl"
  ];
  vendorHash = null;
}
