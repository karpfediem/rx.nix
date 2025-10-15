# `rx.nix` Flake Module

This directory contains the **flake-part** that exposes `rx.nix` integration to consumer flakes.  
It bridges NixOS configurations (`nixosConfigurations`) with the `rx.nix` intermediate representation and generation pipeline.

---

## Overview

The flake module provides all the top-level flake outputs for `rx.nix`, including:

| Output | Description |
|---------|-------------|
| `rxSystems.<system>.<host>` | Per-system generations built from the host IR |
| `rxIrForHost.<host>` | IR JSON for a single host |
| `rxGenForHost.<host>` | Complete build of that host’s reactive generation |
| `apps.rxSwitchForHost.<host>` | Switch-to-configuration wrapper for that host |
| `perSystem.rx-ir` / `perSystem.rx-selected` | System-scoped IR builders for bulk evaluation |

The flake module is intended to be imported by consumer projects using flake-parts:

```nix
{
  imports = [
    rxnix.flakeModules.default
  ];
}
```

This automatically discovers `nixosConfigurations` defined in the consumer flake and exposes their corresponding reactive build outputs.

---

## Architecture

```
flake-module/
├── default.nix                # Entry point: defines flake outputs and perSystem parts
├── lib/
│   ├── build-gens.nix         # Builds mgmt-ready generations (payload, mgmt.mcl, switch)
│   ├── discover-hosts.nix     # Enumerates and normalizes nixosConfigurations
│   ├── gen-for-host.nix       # Builds per-host rxIrForHost/rxGenForHost/apps
│   ├── ir-for-system.nix      # Computes per-system IR from selected resources
│   ├── project-ir.nix         # Converts IR objects into a serializable JSON structure
│   ├── merge/
│   │   └── files-from-includes.nix  # Merges include rules and etc definitions
│   ├── origins/
│   │   ├── etc-origins.nix         # Extracts /etc/ files from environment.etc.*
│   │   └── systemd-origins.nix     # Extracts systemd services for potential mgmt svc mapping
│   ├── policy/
│   │   ├── collect-policies.nix    # Collects user-defined whitelist/exclusion policies
│   │   └── match-policy.nix        # Matches definitions against policies
│   └── select/
│       ├── select-files.nix        # Applies file-level selection and filtering
│       ├── select-packages.nix     # (future) Selects managed packages
│       └── select-systemd.nix      # (future) Selects managed systemd units
```

---

## High-Level Flow

1. **Host Discovery**

    * `discover-hosts.nix` enumerates all hosts under `nixosConfigurations`.

2. **Policy Collection**

    * `collect-policies.nix` and `match-policy.nix` gather user-defined include/exclude rules:

      ```nix
      rx.include.by-policy."/nixos/modules/system/boot".files.enable = true;
      rx.exclude.files."/etc/resolv.conf".enable = true;
      ```

3. **Origin Analysis**

    * `origins/etc-origins.nix` and `origins/systemd-origins.nix` extract structured definitions from NixOS options.

4. **Selection**

    * `select-files.nix` filters environment.etc entries and custom rx.files based on policy.

5. **Intermediate Representation**

    * `ir-for-system.nix` builds a normalized `{ files = [ … ]; }` IR per host.

6. **Generation**

    * `project-ir.nix` and `build-gens.nix` serialize IR to JSON, create the `payload/`, and generate `mgmt.mcl` plus `switch-to-configuration`.

7. **Flake Outputs**

    * The flake module wires everything together:

        * `rx-ir` / `rx-selected` for all hosts
        * `rxIrForHost` / `rxGenForHost` / `apps.rxSwitchForHost` for single hosts

---

## Design Philosophy

* **Host-first** — Output structure mirrors `nixosConfigurations`.
* **System-independent** — Evaluations use each host’s declared target system.
* **Strict separation** — Policy collection, resource discovery, and IR projection are isolated.
* **Composable** — Additional resource types (e.g., `systemd`, `pkg`) can be added incrementally.

---

## Extending

To add new resource types (e.g., packages, users, services):

1. Implement an origin extractor under `lib/origins/`.
2. Add a selector under `lib/select/` that filters matching resources.
3. Extend `ir-for-system.nix` to include the new resource type in the IR.
4. Add mgmt mapping logic in `project-ir.nix` and `build-gens.nix`.

Each addition is self-contained, following the same pattern as `files`.
