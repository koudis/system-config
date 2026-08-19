# Tool Requirements: CMake

Inherits everything in [general.md](general.md).

## 1. Purpose

The build system. Required by this repository itself, because the Neovim build
depends on it.

## 2. Classification

Currently a **build input** (GEN-D-6). It SHOULD be reclassified as a **dev
tool** (GEN-D-9).

**CMAKE-R-1** CMake SHALL be obtained as a pinned prebuilt binary rather than
compiled, unless a build-configuration requirement is recorded that makes a
source build necessary.

**CMAKE-A-1** No such requirement exists. Unlike Neovim, which needs a specific
build type (see that document), CMake is built here with default settings only.
Nothing is gained by compiling it. `VERIFIED` - read from the current setup
script, which passes only a prefix and a parallelism level.

**CMAKE-A-2** The version is available as a pinned prebuilt binary from the
orchestrator's registry, sourced from the upstream project's own releases.
`VERIFIED` - orchestrator registry listing.

## 3. Pin

| Property | Value |
|---|---|
| Version | recorded in the pin registry (GEN-D-16) under key `cmake` |
| Current pin mechanism | submodule gitlink plus a shell constant, in disagreement |
| Required pin mechanism | single entry in the pin file |

**CMAKE-A-3** As with Neovim, the gitlink is not the effective pin; the shell
constant decides the checkout and the tree is cleaned on both sides. Removing
the submodule loses nothing. `VERIFIED` - read from the current setup script.

## 4. Install location

**CMAKE-R-2** The binary SHALL be installed under the application directory
(GEN-R-1a), replacing the separate user binary directory used today.

## 5. Declared inputs

| Input | Source |
|---|---|
| Application directory | global setting (GEN-R-1b) |

**CMAKE-R-3** CMake SHALL be available before the Neovim build runs. This
ordering SHALL be declared, not assumed (GEN-R-5). The current implementation
only checks that some CMake exists on the executable path and would silently
use a system one.

## 6. Fallback

**CMAKE-R-4** If the prebuilt binary is ever unsuitable, the fallback is a
source build from a checksum-verified release archive, with the same install
prefix and the same single pin. The submodule is not reinstated.

## 7. Verification

| Requirement | Check |
|---|---|
| CMAKE-R-1 | Reported version is the pinned version (registry key `cmake`) and no source tree is present after setup |
| CMAKE-R-2 | The binary resolves under the application directory |
| CMAKE-R-3 | The Neovim build succeeds on a machine with no system CMake |
