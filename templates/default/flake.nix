{
  description = "Consumer of rx.nix flakeModules";

  inputs = {
    nixpkgs.url = "github:karpfediem/nixpkgs?ref=update-mgmt-1.0.0";
    flake-parts.url = "github:hercules-ci/flake-parts";

    rx.url = "github:karpfediem/rx.nix";
    rx.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, rx, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({
      # Import the provider's flake module
      # Include a separate config file that sets rx.files (to show how users would do it)
      # The flake-parts way to add more module code is via imports, but inside the consumer
      # we can just include it here too:
      imports = [
        rx.flakeModules.default
      ];
      systems = [ "x86_64-linux" ];

      flake.nixosConfigurations = let lib = nixpkgs.lib; in {
        demo = lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            rx.nixosModules.default # import the rx.nix nixos module
            # You can now use rx module options inside your modules
            ({ ... }: {
              rx.enable = true;
              rx.mgmt.enable = true;

              rx.res.file."/tmp/test" = {
                state = "exists";
                source = "/etc/hosts";
                owner = "carp";
                group = "users";
              };

              rx.res.file."/tmp/hello" = {
                state = "exists";
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
