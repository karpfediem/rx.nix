{ lib, ... }:
{
  rx.file = {
    "/tmp/issue".text = "Authorized access only.\n";
    "/tmp/copied.txt".source = ./copied.txt;

    "/tmp/app/config.json" = {
      generator = lib.generators.toJSON { };
      value = { debug = false; api = "https://example.local"; };
      mode = "0640";
    };
  };
}
