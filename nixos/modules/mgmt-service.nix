# nixos/modules/mgmt-service.nix
{ lib, pkgs, config, ... }:

let
  inherit (lib)
    mkIf mkMerge mkEnableOption mkOption mkDefault types;
  cfg = config.rx.mgmt;
in {
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
      # Absolute path literal is fine here.
      default = /nix/var/nix/profiles/mgmt/current;
      description = "Profile symlink updated by rx switchers";
    };
  };

  config = mkMerge [
    # System service when no user is specified
    (mkIf (cfg.enable && cfg.user == null) {
      systemd.services.mgmt-apply = {
        description = "mgmt reactive apply (rx.nix)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${cfg.package}/bin/mgmt run lang ${cfg.profilePath}/deploy/metadata.yaml --no-network";
          Restart = "always";
          RestartSec = 2;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };
    })

    # User service when a user is specified
    (mkIf (cfg.enable && cfg.user != null) {
      systemd.user.services.mgmt-apply = {
        description = "mgmt reactive apply (rx.nix, user)";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${cfg.package}/bin/mgmt run lang ${cfg.profilePath}/deploy/metadata.yaml --no-network";
          Restart = "always";
          RestartSec = 2;
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };

      # Ensure the user's lingering is enabled so the user unit starts at boot.
      users.users.${cfg.user}.linger = mkDefault true;
    })
  ];
}
