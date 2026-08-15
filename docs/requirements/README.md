# Requirements Documentation

Requirements for this system-configuration repository, written as statements of
intent rather than implementation. These documents describe *what must be true*;
the migration plan in [../spec-mise-migration.md](../spec-mise-migration.md)
describes *how it will be achieved*.

These documents contain no code by design. Package names, version numbers and
file paths appear because they are facts to be recorded, not because they are
instructions to be executed.

## Structure

| Document | Contents |
|---|---|
| [general.md](general.md) | Definitions, global assumptions, global requirements. Everything below inherits it. |
| [tool-zsh.md](tool-zsh.md) | Login shell, framework, theme, environment |
| [tool-neovim.md](tool-neovim.md) | Editor, built from source |
| [tool-cmake.md](tool-cmake.md) | Build system |
| [tool-cmakelib.md](tool-cmakelib.md) | CMake library and its five components |
| [tool-go.md](tool-go.md) | Go toolchain - currently unmanaged |
| [tool-kitty.md](tool-kitty.md) | Terminal emulator - the simplest case |
| [tool-desktop-apps.md](tool-desktop-apps.md) | Seventeen Flatpak applications |
| [../adding-a-new-tool.md](../adding-a-new-tool.md) | The procedure for adding a managed tool |

## How to read a tool document

Each one follows the same shape: purpose, classification, pins, prerequisites,
declared inputs, requirements, and verification. The classification is the most
important field - it determines almost everything else, and the rule for
choosing it is in general.md section 2.

## Conventions

Identifiers are stable. `GEN-R-4` means the same thing everywhere and may be
cited from anywhere. Requirements are never renumbered; a withdrawn requirement
is marked withdrawn and its number is retired.

Every assumption carries a validation status. `VERIFIED` means it was checked
against an authoritative upstream source or against a real machine, with the
source named. An assumption with no status is a guess and SHALL NOT be relied
upon.

**Every assumption in the set is now `VERIFIED` and there are no open
decisions.** The two items that were outstanding have been closed:

- `APPS-A-5` - the orchestrator does **not** configure Flatpak remotes; an
  explicit preceding step is required (`APPS-R-7`).
- `APPS-A-4` - desktop applications install **system-wide**, matching current
  behaviour (`APPS-R-6`).

## Scope

Fedora is the only supported platform (`GEN-A-2`). Package names are recorded
for Fedora and nothing else, and operating-system conditionals are prohibited
outright rather than centralised (`GEN-R-8`).

## Requirement language

**SHALL** is mandatory. **SHOULD** is a strong default that may be overridden
with a recorded reason. **MAY** is optional.
