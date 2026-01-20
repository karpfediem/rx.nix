# `rx.nix` - Reactive Nix

> **Enabling Functional Reactive Configuration with mgmt**


## Motivation

Nix lets us define entire systems as pure functions - deterministic, reproducible, and immutable.
Each build yields a perfectly reproducible system generation, a snapshot of declarative intent made concrete.

However, once evaluated, these functions produce *fixed values*: the system stops evolving until we rebuild it.
The world changes - secrets rotate, services start, fail and stop, peers reappear on the network - but the configuration does not react.

### The missing dimension: time

In Nix, a derivation represents a pure mathematical function:

```go
system = f(configuration)
```

This guarantees purity and reproducibility - but it also locks time out of the model.
A system generation can be correct now and outdated a moment later, and the only way to react is to rebuild.

**Functional Reactive Programming (FRP)** extends this idea:

```go
system(t) = f(configuration, environment(t))
```

Here, configurations remain pure, yet they depend on **signals** - values that evolve continuously as their environment changes.
FRP enables declarative systems that stay correct over time.

---

## The Idea

**`rx.nix`** (Reactive Nix) explores how Nix's functional evaluation model can integrate with **mgmt's** FRP runtime - a configuration management engine that reacts to change in real time.

While Nix provides the *specification* of a system, `mgmt` provides the *motion*:
a continuous reconciliation loop that enforces the declared state automatically.

The combination is simple but potentially very powerful:

* Nix defines **what** the system should look like.
* mgmt ensures it **stays that way** - continuously, safely, and declaratively.

This fusion opens the door to systems that are not only reproducible at build time but **reactively self-correcting** at runtime.

---

## Current Struggles

**1. Static evaluation**
Nix systems are static between rebuilds. Drift or external changes require explicit intervention.

**2. Secret management**
Secrets in Nix are typically static, baked into store paths or decrypted at build time.
Integrating a reactive engine allows external secret stores (Vault, 1Password, etc.) to feed live data into configuration safely.

**3. Declarative dynamic Configuration**
Today, "dynamic" configuration in Nix often means templating or scripting (custom logic running on activation, or as a background service).
FRP makes *pure dynamism* possible - logic that depends on live system signals while preserving functional semantics.

**4. State awareness**
Traditional Nix evaluation is blind to runtime state. mgmt introduces live feedback loops that can reapply, heal, or reconfigure in response to drift or dependency changes.

---

## How It Works

`rx.nix` is a **nixos module** that lets users define reactive configuration inside regular nixosConfigurations.
It also provides additional outputs via a flake module.

### Example

```nix
{
  imports = [ rx.flakeModules.default ];

  nixosConfigurations.demo = lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      rx.nixosModules.default
      ({ ... }: {
        rx.enable = true; # enable module
        rx.mgmt.enable = true; # enable mgmt systemd service

        rx.mcl.imports = [ "datetime" "golang" ]; # set up required imports (either here or in MCL code)
        rx.mcl.vars.d = "datetime.now()"; # reactive variables

        # Write raw MCL code
        # Define your own reactive files (try to `watch -n 0.1 cat /tmp/now`)
        rx.mcl.raw = [
          ''
            file "/tmp/now" {
              state => $const.res.file.state.exists,
              content => golang.template("Hello! It is now: {{ datetime_print . }}\n", $d),
            }
          ''
        ];
      })
    ];
  };
}
```
The nixosModule will generate a bundled up MCL module and set it as your current profile on system activation.
The included systemd service will ensure your configuration is applied continuously during runtime of your system.

Additionally, the flake module provides these new outputs:

| Output                        | Description                             |
| ----------------------------- | --------------------------------------- |
| `rxSystems.<system>.<host>`   | Built mgmt generations per host         |
| `rxIrForHost.<host>`          | Per-host intermediate representation    |
| `rxGenForHost.<host>`         | Materialized mgmt configuration payload |
| `apps.rxSwitchForHost.<host>` | CLI app to switch the active generation |

---

## Example IR

```json
{
  "demo": {
    "files": [
      {
        "path": "/etc/hosts",
        "owner": "root",
        "mode": "0644",
        "__source": "/nix/store/...-hosts"
      },
      {
        "path": "/tmp/hello",
        "owner": "root",
        "mode": "0644",
        "__content": "Hello from rx module\n"
      }
    ]
  }
}
```

This **Intermediate Representation (IR)** serves as the bridge between Nix's static world and mgmt's reactive runtime.

---

## Vision & Motivation

**Reactive Nix** isn't about replacing NixOS or mgmt.
It's about exploring what happens when we bring *time* into functional configuration.

The questions driving this project are:

* Can we cleanly combine purity and reactivity without giving up determinism?
* Which new possibilities emerge when configuration is truly *alive*?

---

## Rough Roadmap

| Phase | Feature / Exploration                                  | Status        |
|-------|--------------------------------------------------------|---------------|
| I     | File resources (`rx.files`, `rx.include.files`)        | ✅ Implemented |
| II    | Per-host evaluation (`rxGenForHost`, `rxIrForHost`)    | ✅ Implemented |
| III   | Full MCL resource mapping (via codegen)                | ✅ Implemented |
| IV    | External secrets integration (Vault, 1Password, SOPS)  | 🔄 Planned    |
| V     | Live mgmt evaluation backend (MCL codegen refactor)    | 🔄 Planned    |
| VI    | Full dynamic dependencies (signals between hosts)      | 🚧 Research   |
| VII   | Cross-platform expansion (macOS via nix-darwin)        | 🚧 Research   |
| VIII  | Conceptual FRP primitives in Nix (mkSignal, mkDynamic) | 🚧 Research   |
