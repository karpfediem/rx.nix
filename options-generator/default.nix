{ pkgs
}:
pkgs.buildGoModule {
  pname = "options-generator";
  version = "0.1.0";
  src = ./.;
  vendorHash = "sha256-Ybe6Gv86hw7uiRw69lHu0JAffG0TEGsicFgffrwDdjw=";
}
