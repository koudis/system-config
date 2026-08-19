# Tool Requirements: CMakeLib

Inherits everything in [general.md](general.md).

## 1. Purpose

A CMake library and its components, consumed by projects outside this
repository through environment variables.

## 2. Classification

**Runtime content** (GEN-D-7). It is never compiled and never installed. It is
a set of source trees read directly by CMake at build time in other projects.
It lives inside the application directory, not the repository (GEN-R-3): it
is not the fixed-path exception that GEN-R-3 records, so it follows the
general case.

## 3. Pins

Five separate sources, all currently submodules.

| Component | Pin | Recorded as |
|---|---|---|
| cmakelib | recorded in the pin registry (GEN-D-16) under key `CMLIB_REF` | commit SHA |
| component-cmconf | recorded in the pin registry (GEN-D-16) under key `CMLIB_CMCONF_REF` | tag |
| component-cmdef | recorded in the pin registry (GEN-D-16) under key `CMLIB_CMDEF_REF` | tag |
| component-cmutil | recorded in the pin registry (GEN-D-16) under key `CMLIB_CMUTIL_REF` | commit SHA |
| component-storage | recorded in the pin registry (GEN-D-16) under key `CMLIB_STORAGE_REF` | commit SHA |

**CMLIB-A-1** One of the five is currently an orphaned gitlink: it exists in the
tree but is not declared, so the submodule status command fails outright and a
recursive clone silently under-populates the set. `VERIFIED` - nine gitlinks
against eight declarations.

**CMLIB-A-2** All five currently use SSH URLs, which cannot be cloned on a fresh
machine before a key is uploaded. This is the single most direct violation of
the repository's purpose. `VERIFIED` - four declared SSH URLs plus the
undeclared fifth.

**CMLIB-R-1** All five SHALL be fetched over HTTPS anonymously (GEN-A-4) and all
five SHALL be declared. Three carry usable tags and SHOULD be pinned by tag; two
sit between tags and SHALL be pinned by SHA.

`CORRECTED 2026-08-19`: the index table above carried a restated tag value for
component-storage, and it was stale - the component is pinned by SHA in the
pin registry, as the other two SHA-pinned components are. The row now names
its registry key like every sibling row (GEN-R-20). The split is therefore two
by tag and three by SHA, not three and two; the requirement's normative
sentence is left as written, because which components happen to sit on a
usable tag is a fact about upstream at a moment in time, not a rule this
repository imposes.

## 4. Declared inputs and outputs

**CMLIB-R-2** This tool exports two environment values: the library directory
and the component search base path.

**CMLIB-R-3** These values SHALL be declared as this tool's outputs and consumed
explicitly by the shell configuration. They SHALL NOT be emitted as a side
effect of configuring the shell (GEN-R-9).

**CMLIB-A-3** Today the situation is inverted: this tool's setup step does
nothing at all, and the environment is emitted from the shell's template. The
coupling is recorded only in a source comment. This is the clearest instance of
the hidden-coupling defect in the repository. `VERIFIED` - the setup step
contains only a no-op, and the values appear in the shell template.

## 5. Verification

| Requirement | Check |
|---|---|
| CMLIB-R-1 | A fresh clone with no SSH key populates all five components |
| CMLIB-R-1 | Each component reports the pinned tag or SHA |
| CMLIB-R-3 | Both environment values are traceable to this document, and the shell template declares them as inputs |
