{ lib, pkgs, config, ... }:

let
  inherit (lib)
    mkIf mkMerge mkEnableOption mkOption mkDefault
    types escapeShellArg optionalString concatStringsSep
    makeBinPath makeSearchPath escapeShellArgs;

  cfg = config.rx.mgmt;

  defaultStateName = "mgmt";

  defaultDataDir =
    if cfg.user == null
    then "/var/lib/${cfg.stateName}"
    else "%S/${cfg.stateName}";

  dataDir = if cfg.dataDir != null then cfg.dataDir else defaultDataDir;

  # ---- 1) Construct per-host IR directly from this host's NixOS config ----
  hostIR =
    let
      rx = config.rx or { };
      mcl = rx.mcl or { };
    in
    {
      imports = lib.lists.unique ([ "deploy" ] ++ (mcl.imports or [ ]));
      vars = mcl.vars or { };
      raw = mcl.raw or [ ];
      res = (rx.res or { });
    };

  # ---- 2) Build deploy derivation for this host ----
  deployName = config.networking.hostName or "host";
  moduleDrv = pkgs.callPackage (import ../../pkgs/module.nix { inherit deployName; ir = hostIR; }) { };

  # ---- 3) Scripts embedded into the generation output ----
  rxGeneration = pkgs.callPackage ../../pkgs/generation.nix { inherit deployName moduleDrv; };

  rxSwitchPkg = pkgs.writeShellApplication {
    name = "rx-switch";
    runtimeInputs = with pkgs; [
      bash
      nixVersions.latest
      systemdMinimal
      coreutils-full
    ];
    text = ''
      set -euo pipefail
      GEN=${escapeShellArg rxGeneration}
      exec "$GEN/switch-to-configuration" "$GEN"
    '';
  };

  # PATH pieces from user-provided packages.
  extraBinPath = makeBinPath cfg.path;
  extraSbinPath = makeSearchPath "sbin" cfg.path;

  extraPkgPath =
    concatStringsSep ":" (lib.filter (s: s != "") [ extraBinPath extraSbinPath ]);

  # mgmt invocation:
  # Put mgmt "run" flags BEFORE the "lang" subcommand; this matches documented examples.
  mgmtArgs =
    [ "run" ]
    ++ cfg.runArgs
    ++ [
      "lang"
      "${cfg.profilePath}/deploy/metadata.yaml"
      "--no-network"
      "--prefix"
      dataDir
    ];

  mgmtExec = pkgs.writeShellScript "mgmt-exec" ''
    set -euo pipefail

    # Keep systemd’s default PATH, but ensure common NixOS “profiles” are visible.
    export PATH="/run/current-system/sw/bin:/run/current-system/sw/sbin:/run/wrappers/bin:$PATH${optionalString (extraPkgPath != "") ":${extraPkgPath}"}"

    exec ${cfg.package}/bin/mgmt ${escapeShellArgs mgmtArgs}
  '';

in
{
  options.rx.mgmt = {
    enable = mkEnableOption "Run mgmt continuously against the rx.nix profile";

    package = mkOption {
      type = types.package;
      default = pkgs.mgmt;
      description = "mgmt package to use for the mgmt service";
    };

    path = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        Extra packages to add to the PATH of the mgmt systemd unit.

        This is appended at runtime (in a wrapper script) using lib.makeBinPath
        (and also /sbin via lib.makeSearchPath "sbin"), so mgmt can find
        external tools it execs (eg groupadd/useradd/etc) without overriding
        the default systemd PATH option.
      '';
    };

    # extra flags for "mgmt run ..."
    runArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra command-line arguments inserted after `mgmt run` and before `lang ...`.

        Use this to configure etcd/seeds/ssh tunnelling/etc, e.g.:
          [ "--no-server" "--seeds=http://10.0.2.2:2379" ].
      '';
    };

    # extra environment variables for the unit
    env = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Extra environment variables to pass to the mgmt systemd unit.
        This is merged into the unit's `environment` attribute.
      '';
    };

    user = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "If set, install a user service for this user instead of a system service.";
    };

    profilePath = mkOption {
      type = types.path;
      default = "/nix/var/nix/profiles/mgmt/current";
      description = "Profile symlink updated by activation/switchers";
    };

    stateName = mkOption {
      type = types.str;
      default = defaultStateName;
      description = "Name for systemd-managed state directory.";
    };

    dataDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Override persistent data directory for mgmt runtime state.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Expose the generation and switch package under build for debugging/introspection
    {
      system.build.rxGeneration = rxGeneration;
      system.build.rxSwitchPkg = rxSwitchPkg;
    }

    # Provide rx-switch command
    { environment.systemPackages = [ rxSwitchPkg ]; }
    # Provide packages in system closure (prevent download during no-network activation scripts)
    # These need to include the runtime deps of the switcher scripts
    {
      system.extraDependencies = with pkgs; [
        rxGeneration
        rxSwitchPkg
        bash
        nixVersions.latest
        systemdMinimal
        coreutils-full
      ];
    }

    # Activation: set mgmt profile to the generation produced by this config
    (mkIf (cfg.user == null) {
      system.activationScripts.rxSwitch = {
        deps = [ "etc" "usrbinenv" ];
        text = "${rxSwitchPkg}/bin/rx-switch";
      };
    })

    # Systemd system service
    (mkIf (cfg.user == null) {
      systemd.services.mgmt = {
        description = "mgmt reactive apply (rx.nix)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = cfg.env;

        serviceConfig = {
          Type = "simple";
          ExecStart = mgmtExec;

          # mgmt is a configuration management tool. It will very likely need to read and modify the real filesystem.
          PrivateTmp = false;
          ProtectSystem = "off"; # equivalent to not setting it; explicit for clarity
          ProtectHome = false;
          # TODO restrict permissions if possible (PoC for now)
          User = "root";
          Group = "root";

          # Keep a dedicated state dir for mgmt runtime data (etcd, caches, etc.)
          WorkingDirectory = dataDir;
          StateDirectory = cfg.stateName;
          StateDirectoryMode = "0750";

          Restart = "always";
          RestartSec = 2;

          # Not expecting privilege transitions via setuid.
          NoNewPrivileges = true;
        };
      };
    })

    # Systemd user service
    # Activation switching is not yet implemented.
    (mkIf (cfg.user != null) {
      systemd.user.services.mgmt = {
        description = "mgmt reactive apply (rx.nix, user)";
        wantedBy = [ "default.target" ];

        environment = cfg.env;

        serviceConfig = {
          Type = "simple";
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p -- ${dataDir}";
          ExecStart = mgmtExec;

          Restart = "always";
          RestartSec = 2;

          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };

      users.users.${cfg.user}.linger = mkDefault true;
    })
  ]);
}
