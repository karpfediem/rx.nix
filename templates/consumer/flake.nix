{
  description = "Consumer of rx.nix flakeModules";

  inputs = {
    nixpkgs.url = "github:karpfediem/nixpkgs?ref=update-mgmt-1.0.0";
    flake-parts.url = "github:hercules-ci/flake-parts";

    rxnix.url = "git+file:///home/carp/code/rx.nix";
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

              rx.res.file."/tmp/test" = {
                source = "/etc/hosts";
                owner = "carp";
                group = "users";
              };

              rx.res.file."/tmp/hello" = {
                content = "Hello from rx module\n";
                owner = "carp";
                group = "users";
              };

              rx.mcl.imports = [ "datetime" "golang" ];
              rx.mcl.vars.d = "datetime.now()";
              rx.mcl.raw = [
                ''
                  file "/tmp/mgmt/datetime" {
                    state => $const.res.file.state.exists,
                    owner   => "carp",
                    group   => "users",
                    content => golang.template("Hello! It is now: {{ datetime_print . }}\n", $d),
                  }

                  file "/tmp/mgmt/" {
                    owner   => "carp",
                    group   => "users",
                    state => $const.res.file.state.exists,
                  }
                ''
              ];
            })
            ./configuration.nix
          ];
        };
      };
    });
}
