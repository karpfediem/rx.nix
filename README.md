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

`rx.nix` is a **flake module** that augments regular Nix flakes with reactive outputs.

### Example

```nix
{
  imports = [ rxnix.flakeModules.default ];

  nixosConfigurations.demo = lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      rxnix.nixosModules.default
      ({ ... }: {
        rx.enable = true;

        # Whitelist system resources
        rx.include.files."/etc/hosts".enable = true;

        # Define your own reactive files
        rx.files."/tmp/hello".text = "Hello from rx.nix\n";
      })
    ];
  };
}
```

This gives your flake new outputs:

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

| Phase | Feature / Exploration                                  | Status             |
| ----- | ------------------------------------------------------ | ------------------ |
| I     | File resources (`rx.files`, `rx.include.files`)        | ✅ Implemented     |
| II    | Per-host evaluation (`rxGenForHost`, `rxIrForHost`)    | ✅ Implemented     |
| III   | Systemd services (`svc`) resources                     | 🔄 In progress     |
| IV    | External secrets integration (Vault, 1Password, SOPS)  | 🔄 Planned         |
| V     | Live mgmt evaluation backend (MCL codegen refactor)    | 🔄 Planned         |
| VI    | Full dynamic dependencies (signals between hosts)      | 🚧 Research        |
| VII   | Cross-platform expansion (macOS via nix-darwin)        | 🚧 Research        |
| VIII  | Conceptual FRP primitives in Nix (mkSignal, mkDynamic) | 🚧 Research        |
