# Tool Requirements: Go

Inherits everything in [general.md](general.md).

## 1. Purpose

The Go toolchain. Present in the environment today but managed by nothing.

## 2. Classification

**Dev tool** (GEN-D-9). Pinned and installed by this repository, independent of
the operating system. The SDK is an installed artifact (GEN-D-14) and lives
under the application directory (GEN-D-13).

## 3. Status: currently unmanaged

**GO-A-1** No part of this repository installs Go. The shell configuration
nevertheless injects a Go binary directory into the executable search path,
using a path hardcoded to one specific SDK version inside the application
directory. On a fresh machine that path does not exist, so the search path
contains a dangling entry from first login. `VERIFIED` - the path appears in a
helper function that nothing installs against, and the directory is absent on
this machine.

**GO-A-2** The guard intended to catch this cannot. It tests only whether the
configured string is empty, never whether the directory exists, so an absent
SDK passes silently. `VERIFIED` - read from the helper.

**GO-R-1** Go SHALL be a declared, pinned tool with a single entry in the pin
file, installed by setup like every other tool.

## 4. Pin

| Property | Value |
|---|---|
| Version | 1.23.3 - the version the hardcoded path refers to |
| Current pin mechanism | none; a literal path fragment |
| Required pin mechanism | single entry in the pin file |

**GO-A-3** Go is a first-class tool in the orchestrator's own tool set, so no
plugin or custom backend is required. Plain version numbers are accepted for
1.21 and later; only 1.20 and earlier require special version syntax. At 1.23.3
the plain form applies. `VERIFIED` - orchestrator language documentation.

## 5. Path exposure

**GO-R-2** The hardcoded path fragment SHALL be removed from the shell template.
Visibility of the Go binaries SHALL come from the orchestrator's shell
activation, which covers every installed tool uniformly (see ZSH-R-11).

**GO-R-3** No consumer SHALL reference the Go SDK by literal path. The version
appears once, in the pin file (GEN-R-7).

## 6. Related deletion

**GO-A-4** The same shell template carries a Haskell environment line pointing
at an absolute path containing a literal username. It is dead: the directory
does not exist, none of the Haskell toolchain binaries are present, and the
repository contains no Haskell sources - the only file of that type is a test
fixture belonging to an editor plugin. Its existence guard is why it fails
silently rather than erroring. `VERIFIED` - checked on this machine.

**GO-R-4** That line SHALL be deleted. If a Haskell toolchain is wanted later it
returns as a pinned tool under this document's pattern, not as a literal path in
a template.

## 7. Verification

| Requirement | Check |
|---|---|
| GO-R-1 | Go reports version 1.23.3 after setup on a clean machine |
| GO-R-2 | Every entry in the resulting search path exists |
| GO-R-3 | Searching the repository for a literal Go SDK path returns nothing |
| GO-R-4 | Searching the repository for the Haskell environment path returns nothing |
