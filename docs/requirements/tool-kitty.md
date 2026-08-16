# Tool Requirements: Kitty

Inherits everything in [general.md](general.md).

## 1. Purpose

The terminal emulator.

## 2. Classification

| Part | Classification |
|---|---|
| The emulator | System package (GEN-D-8) |
| Its configuration | Repository content, committed, deployed by link (GEN-D-11) |

Nothing is built and nothing is pinned by this repository.

## 3. System package

**KITTY-R-1** The Fedora package is named `kitty`. Unlike the Silver Searcher
case (see the Zsh document), the binary name and package name coincide here;
this SHALL still be recorded explicitly rather than assumed (GEN-R-14).

## 4. Configuration deployment

**KITTY-R-2** The configuration file is committed, not rendered. It contains no
placeholders and needs none.

**KITTY-R-3** Deployment SHALL create the parent directory before creating the
link, and SHALL replace an existing symbolic link at the target that already
resolves into this repository.

**KITTY-R-4** Deployment SHALL NOT replace anything else at the target. An
existing real file, or a symbolic link pointing outside this repository, is
something setup did not create and may be the only copy of the user's own
configuration; the step fails and names the path instead (GEN-R-17b). This
narrows the earlier wording of KITTY-R-3, which said any existing link or file
was to be replaced. Replacing the correct link silently is what keeps re-runs
idempotent; replacing anything else is data loss, and the harness always runs
in a throwaway container where that loss would never be observed.

**KITTY-A-1** This is the repository's clearest idempotence defect. The current
step creates the link without replacing an existing one and without creating the
parent directory. It therefore fails on the second run always, and fails on the
first run whenever the emulator has not already created its own configuration
directory - which on a genuinely fresh machine is the normal case, because the
package is installed in the same run and has never been launched. `VERIFIED` -
read from the current setup step; the two sibling tools both do the removal step
that this one omits.

## 5. Declared inputs

None. This tool consumes no value from any other tool and exports none. It is
the simplest managed tool in the repository and is the reference example in
[adding-a-new-tool.md](../adding-a-new-tool.md).

## 6. Verification

| Requirement | Check |
|---|---|
| KITTY-R-1 | The package installs on a clean Fedora machine |
| KITTY-R-3 | Setup runs twice in succession without error on a machine where the emulator has never been launched |
| KITTY-R-3 | The deployed path is a link pointing into the repository |
| KITTY-R-4 | With a real file placed at the target, setup exits non-zero, names the path, and the file's contents are unchanged |
