{
  description = "Consumer of rx.nix flakeModules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    rxnix.url = "github:karpfediem/rx.nix";
    rxnix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, rxnix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({
      # Import the provider's flake module
      # Include a separate config file that sets rx.files (to show how users would do it)
      # The flake-parts way to add more module code is via imports, but inside the consumer
      # we can just include it here too:
      imports = [
        rxnix.flakeModules.default
      ];
      systems = [ "x86_64-linux" ];

      flake.nixosConfigurations = let lib = nixpkgs.lib; in {
        demo = lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            rxnix.nixosModules.default # import the rxnix nixos module
            # You can now use rx module options inside your modules
            ({ ... }: {
              rx.enable = true;

              # pick exactly one file
              rx.include.files."/etc/hosts".enable = true;

              # (optional) override something so you can see it flow through
              rx.include.files."/etc/hosts".mode = "0644";

              rx.files."/tmp/hello".text = "Hello from rx module\n";
            })
            ./configuration.nix
          ];
        };
      };
    });
}
