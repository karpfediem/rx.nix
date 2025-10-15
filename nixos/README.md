# `rx.nix` NixOS Module Layer

This directory contains the **NixOS module definitions** that expose reactive configuration options (`rx.*`) inside standard NixOS systems.

These modules are responsible for making `rx.nix` feel like a native NixOS feature — the same option syntax, type safety, and evaluation semantics.

---

## Overview

The module tree provides the declarative interface for users:

```nix
{
  rx.enable = true;

  # Explicitly include system resources for reactive management
  rx.include.files."/etc/hosts".enable = true;

  # Define your own managed files
  rx.files."/tmp/hello".text = "Hello from rx.nix\n";
}
````

All these options are collected by the flake module layer and translated into the mgmt-compatible Intermediate Representation (IR).

---

## Module Layout

```
nixos/
├── default.nix             # Combines all rx submodules
└── modules/
    ├── rx.nix              # Root rx.* option definitions (enable, include/exclude trees)
    └── files/
        ├── default.nix     # Entry point for rx.files.*
        └── options.nix     # Type schema for rx-managed files
```

---

## Modules Explained

### `modules/rx.nix`

Defines the high-level namespace and shared configuration structure:

* `rx.enable` — global flag to enable reactive configuration export
* `rx.include.*` — inclusion tree, subdivided by resource type (files, systemd, packages)
* `rx.exclude.*` — exclusion tree, same structure as include
* `rx.include.by-policy` — pattern-based policy mechanism

Example:

```nix
rx.include.by-policy."/nixos/modules/system/boot".files.enable = true;
rx.exclude.files."/etc/pam.d/login".enable = true;
```

### `modules/files/options.nix`

Defines the schema for `rx.files.*` resources:

```nix
rx.files."<path>" = {
  text       = "...";       # or
  source     = ./some-file; # or
  generator  = fn; value = arg;
  owner      = "root";
  group      = "root";
  mode       = "0644";
  ensureDir  = true;
};
```

Exactly one of `text`, `source`, or `generator+value` must be set.
Defaults are provided to mimic NixOS’s `environment.etc` semantics.

### `modules/files/default.nix`

Imports `options.nix` and binds it under the `rx.files` namespace.
In the future, this may also include validation logic for mgmt conversion.

---

## Evaluation Model

The NixOS modules are evaluated during regular NixOS configuration.
When `rx.enable = true`, they inject their options into the flake-parts evaluation pipeline, but **do not modify the NixOS system** themselves.

This design ensures:

* Safe coexistence with pure NixOS builds.
* Deterministic behavior regardless of whether `rx` is enabled.
* Easy introspection via:

  ```bash
  nix repl
  nixosConfigurations.<host>.config.rx
  ```

---

## Extending

To add new resource categories:

1. Create a subdirectory under `nixos/modules/` (e.g., `systemd/`).
2. Define `options.nix` for that resource type.
3. Import it from `nixos/default.nix`.
4. Extend the flake-module’s `lib/select/select-*.nix` to match and project it.

Each new resource family is both a **NixOS option** and an **IR projection** path.

---

## Design Principles

* **Native to NixOS** — identical option syntax and typing.
* **Minimal coupling** — modules define structure, not behavior.
* **Compositional** — everything lives under `rx.*` namespace.
* **Future-proof** — resource definitions can be extended without breaking consumers.

---

## Example Inspection

```bash
nix repl
nix-repl> :lf .
nix-repl> nixosConfigurations.demo.config.rx.files
{
  "/tmp/hello" = {
    text = "Hello from rx.nix\n";
    owner = "root";
    group = "root";
    mode = "0644";
    ensureDir = true;
  };
}
```

---

## Summary

The `nixos/` layer defines what users write in configuration.

The `flake-module/` layer defines how that configuration becomes an executable, reactive system description.

Together, they form the declarative-to-reactive bridge at the heart of **`rx.nix`**.
