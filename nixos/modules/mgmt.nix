{ lib, pkgs, config, ... }:

let
  inherit (lib) mkIf mkMerge mkEnableOption mkOption mkDefault types escapeShellArg stringAfter;

  cfg = config.rx.mgmt;

  defaultStateName = "mgmt-apply";

  defaultDataDir =
    if cfg.user == null
    then "/var/lib/${cfg.stateName}"
    else "%S/${cfg.stateName}";

  dataDir = if cfg.dataDir != null then cfg.dataDir else defaultDataDir;

  # ---- 1) Construct per-host IR directly from this host's NixOS config ----
  hostIR =
    let
      rx = config.rx or {};
      mcl = rx.mcl or {};
    in
    {
      imports = lib.lists.unique ([ "deploy" ] ++ (mcl.imports or []));
      vars    = mcl.vars or {};
      raw     = mcl.raw or [];
      res     = (rx.res or {});
    };

  # ---- 2) Build deploy derivation for this host ----
  deployName = config.networking.hostName or "host";
  deployDrv = pkgs.callPackage (import ../../lib/build/mkDeploy.nix { ir = hostIR; inherit deployName; }) { };

  # ---- 3) Scripts embedded into the generation output ----
  genPkg = pkgs.callPackage ../../pkgs/switchers.nix { inherit deployName deployDrv; };

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
      GEN=${escapeShellArg genPkg}
      exec "$GEN/switch-to-configuration" "$GEN"
    '';
  };

  execStartCmd =
    "${cfg.package}/bin/mgmt run lang ${cfg.profilePath}/deploy/metadata.yaml --no-network --prefix ${dataDir}";

in
{
  options.rx.mgmt = {
    enable = mkEnableOption "Run mgmt continuously against the rx.nix profile";

    package = mkOption {
      type = types.package;
      default = pkgs.mgmt;
      description = "mgmt package to use for the mgmt-apply service";
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
    # Expose the generation package under build for debugging/introspection
    {
      system.build.rxMgmtGen = genPkg;
      system.build.rxSwitchPkg = rxSwitchPkg;
    }

    # Provide rx-switch command
    { environment.systemPackages = [ rxSwitchPkg ]; }

    # Activation: set mgmt profile to the generation produced by this config
    (mkIf (cfg.user == null) {
      system.activationScripts.rxSwitch = {
        deps = [ "etc" "usrbinenv" ];
        text = "rx-switch";
      };
    })

    # Systemd system service
    (mkIf (cfg.user == null) {
      systemd.services.mgmt-apply = {
        description = "mgmt reactive apply (rx.nix)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = execStartCmd;

          # mgmt is a configuration management tool. It will very likely need to read and modify the real filesystem.
          PrivateTmp = false;
          ProtectSystem = "off";  # equivalent to not setting it; explicit for clarity
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
      systemd.user.services.mgmt-apply = {
        description = "mgmt reactive apply (rx.nix, user)";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p -- ${dataDir}";
          ExecStart = execStartCmd;

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
