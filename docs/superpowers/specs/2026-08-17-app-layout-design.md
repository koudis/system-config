# Application-directory layout and global tool visibility

Design, 2026-08-17. Successor to `2026-08-16-sudo-split-design.md`, written on
branch `sudo-split`.

## 1. Purpose

Two defects motivate this work, and one requested change of shape.

The **defect of scope**: pinned tools resolve only beneath this repository. A
login shell that has left the repository root sees no `go` and the wrong
`cmake`. The migration removed unconditional `PATH` fragments (ZSH-R-10,
ZSH-R-11, GO-R-2) and replaced them with orchestrator activation, which is
directory-scoped. The replacement was narrower than what it replaced, and no
check caught it because every check runs from the repository root.

The **defect of shape**: installed artifacts are scattered. Neovim installs
with the application directory as its CMake prefix, so it writes `bin/`,
`lib64/` and `share/` into the application root. The orchestrator's own tools
live three levels down under a data directory that also holds cache and state.
Fetched runtime content lives inside the repository. There is no single rule
that says where a managed tool's files are.

The **requested shape**: one directory per managed tool, named after the tool,
directly under the application directory.

## 2. Starting state

Branch `sudo-split`, 20 commits ahead of `master`, plus an uncommitted bump of
the Go pin from 1.23.3 to 1.26.6 across four files (`mise.toml`,
`test/checks-tools.sh`, `docs/requirements/tool-go.md`,
`docs/spec-mise-migration.md`). That bump is complete and verified; it is not
part of this design beyond being its trigger.

Current layout:

```
App/
  bin/{mise,nvim}
  lib64/nvim                 <- Neovim, prefix = App/
  share/{nvim,applications,icons,man}
  mise/
    installs/{go,cmake}/<version>/
    <cache and state>
repo/
  _vendor/{cmakelib,cmakelib-component-*,ohmyzsh}
```

## 3. Findings

Each was observed against mise 2026.8.6 on this machine on 2026-08-17.

**F-1 Activation is directory-scoped.** `mise which go` resolves inside the
repository and fails from `$HOME` with "go is a mise bin however it is not
currently active". This is the direct consequence of GEN-A-6: configuration
resolution walks upward from the working directory, so no configuration is in
scope elsewhere.

**F-2 Shims do not fix F-1, and fail unsafely.** With the shim directory on
`PATH` but no configuration in scope, `go` exits non-zero ("No version is set
for shim") and `cmake` **silently executes the system binary**, reporting 4.3.0
instead of the pinned 3.30.1. The shims are symlinks to the orchestrator
binary, which dispatches on `argv[0]`; with no version resolved it defers to
the next match on `PATH`. A silent wrong version is worse than the absence this
was meant to cure. Shims are rejected on this basis, and independently by
stated preference.

**F-3 Pointing the global configuration at the repository file fixes F-1.**
With `MISE_GLOBAL_CONFIG_FILE` set to the repository's `mise.toml`, both tools
resolve correctly from `$HOME`: `go1.26.6` and `cmake 3.30.1`. This holds for
activation with no shims present, and the pin is not duplicated.

**F-4 The install directory is overridable but global.** `MISE_INSTALLS_DIR` is
honoured (setting it changes where the orchestrator looks, which it reports as
"not installed"). It applies to every managed tool at once; there is no
per-tool install path in this release. Moving Go therefore moves CMake.

**F-5 `{{env.APP_DIR}}` resolves in `[env]`.** Verified with a scratch
configuration: an `[env]` entry templated on `env.APP_DIR` expands to the
exported value. Vendored paths can therefore be expressed against the
application directory rather than `config_root`.

**F-6a Both variables must be set in the environment, not in `[env]`.** Upstream
states this explicitly for `MISE_INSTALLS_DIR`: it is read when the orchestrator
starts, and setting it in `[env]` "can make an install use one directory while
later commands and shims look in another". `MISE_GLOBAL_CONFIG_FILE` is
documented as env-var-only for the same reason - configuration discovery has
already happened by the time the configuration file is read. This is GEN-A-7 and
GEN-A-11 again, now with two variables instead of one, and it is why both
exporters are the entry point and the rendered profile.

**F-6b Upstream frames the global configuration file as a write target.** The
documentation describes `MISE_GLOBAL_CONFIG_FILE` as controlling where global
writes such as `mise use` land. Read behaviour is what this design depends on,
and it was observed directly (F-3). Per the precedent GEN-A-8 set, the
observation against the pinned binary outranks the documentation's framing.

**F-7 One fetched source cannot move.** `zsh-autosuggestions` is fetched to
`zsh/custom/plugins/zsh-autosuggestions` inside the repository, because Oh My
Zsh resolves plugins only under its custom plugin directory (ZSH-A-7,
`VERIFIED`) - ZSH-R-12 records this as a correction to an earlier formulation
that had grouped it with the other vendored sources. It is functionally pinned
to that path. Any rewrite of GEN-R-3 therefore **splits** rather than moving
wholesale, and the split needs a stated criterion.

**F-8 `config_root` becomes unsafe in this file.** Once the configuration is
also loaded as the global configuration, `{{config_root}}` no longer reliably
denotes the repository: the global configuration root defaults to `$HOME`. The
two current uses (the cmakelib paths) are replaced by `{{env.APP_DIR}}` under
this design, which removes the hazard - but the prohibition must be recorded, or
the next `{{config_root}}` added to this file will resolve to the wrong root
silently.

**F-6 `prune` did not remove the stale version.** `mise prune --dry-run`
reported it would uninstall `go@1.23.3`; `mise prune` then reported only
"pruned configuration links" and left the install in place. `mise ls
--prunable` listed it throughout. `mise uninstall go@1.23.3` removed it. The
reliable invocation for the "one version per tool" requirement is therefore
unresolved and is the one item the implementation plan must settle empirically
before wiring anything into a task.

## 4. Design

### 4.1 One directory per managed tool

```
App/
  bin/mise               orchestrator bootstrap only
  cmake/<version>/
  cmakelib/
    cmakelib/                     CMLIB_DIR
    cmakelib-component-cmconf/    CMLIB_COMPONENT_LOCAL_BASE_PATH = App/cmakelib/
    cmakelib-component-cmdef/
    cmakelib-component-cmutil/
    cmakelib-component-storage/
  go/<version>/
  mise/                  cache and state only, no installs
  nvim/
    bin/nvim
    lib64/nvim
    share/nvim
  ohmyzsh/
```

The rule: **every managed tool owns one directory under the application
directory, named after the tool.** `App/bin/` retains only the orchestrator
binary, which bootstraps the others and is not itself a managed tool.

`App/cmakelib/` holds the library and its components together, as requested.
This also matches the library's own convention: it resolves components as
`<base>/cmakelib-component-<name>`, so a base of `App/cmakelib/` and a library
path of `App/cmakelib/cmakelib` require no other adaptation.

Mechanisms, by tool:

| Tool | Mechanism | Consequence |
|---|---|---|
| go, cmake | `MISE_INSTALLS_DIR` = application directory | Both move together (F-4); version subdirectory retained |
| nvim | `CMAKE_INSTALL_PREFIX` = `$APP_DIR/nvim` | Stops the `bin`/`lib64`/`share` scatter into the application root |
| cmakelib and components | fetch destination | Ours to choose; five paths change |
| ohmyzsh | fetch destination | `_vendor/` is then empty and is removed |

`zsh-autosuggestions` is deliberately absent from that table: it stays where it
is (F-7). The resulting rule for fetched runtime content is therefore a split
one, and the criterion is stated rather than left implicit:

> Fetched runtime content SHALL live in the application directory, **unless the
> consuming program resolves it only from a fixed path inside the repository**,
> in which case it SHALL be fetched directly to that path and the constraint
> SHALL be recorded as an assumption on the consuming tool.

Today that exception has exactly one member, and ZSH-A-7 is the assumption that
earns it.

### 4.2 Global tool visibility

The rendered login profile SHALL export `MISE_GLOBAL_CONFIG_FILE`, pointing at
this repository's configuration file (F-3). The path is unknown until setup
runs, so it enters the template as a render placeholder alongside the two that
already exist, satisfying ZSH-R-8.

This supersedes GEN-A-6's closing clause, which states that no machine-global
configuration participates in resolution. The assumption's observation about
upward resolution remains correct; what changes is that a global configuration
is now deliberately introduced to extend scope beyond the repository. Following
the APPS-A-9 precedent, GEN-A-6 is **superseded in place, not rewritten**: the
original text stands and the superseding observation is appended.
`docs/spec-mise-migration.md` section 5 carries the same claim and receives the
same treatment.

The pin is not duplicated by this: the global configuration *is* the pin file,
reached by a second route. GEN-R-7 holds unchanged.

### 4.3 One version per tool

Setup SHALL leave exactly one installed version of each managed tool. The
mechanism is unresolved (F-6) and the plan must establish it against the real
binary before it is declared. Acceptance is behavioural, not mechanical: after
a pin bump and a setup run, exactly one version of the bumped tool remains
installed, and it is the pinned one.

### 4.4 Pin registry section

`docs/requirements/general.md` gains a definition and a requirement recording
where pins live and which sources carry one. The section is an **index, not a
second copy**: it names each source and the key under which the pin file
records it, and never restates a value. This is deliberate — the Go bump that
triggered this work had to update three restatements of `1.23.3` in the
requirements set, two of which were already stale.

New identifiers: `GEN-D-16` (pin registry), `GEN-R-20` (index rule). Both
verified free.

### 4.5 Guard weakening, recorded

`fetch_pinned`'s `refuse_if_submodule` uses `git ls-files`, which is meaningful
only for paths inside the repository. Once fetched sources live under the
application directory the check is vacuous for them. The other two guards
(`refuse_if_unregistered_content`, `refuse_if_dirty`) still apply. GEN-R-17a is
weakened, not lost, and SHALL say so rather than continue to claim the
submodule case is covered.

## 5. Requirement changes

| Document | Change |
|---|---|
| `general.md` GEN-D-16, GEN-R-20 | New: pin registry (4.4) |
| `general.md` GEN-A-6 | Superseded in place: a global configuration now participates (4.2) |
| `general.md` GEN-D-7, GEN-D-12, GEN-R-3 | Fetched runtime content moves to the application directory |
| `general.md` GEN-R-1a | "No second install prefix" reworded: the prefix is now per-tool by design |
| `general.md` GEN-R-16 | Two process-start variables to export, not one |
| `general.md` GEN-R-17a | Records the weakening in 4.5 |
| `tool-zsh.md` ZSH-R-13 | A fourth export, and its position |
| `tool-zsh.md` ZSH-R-8, ZSH-R-14 | A third render placeholder |
| `tool-go.md` GO-R-2 | Visibility is machine-wide again, by global configuration |
| `tool-zsh.md` ZSH-R-12 | Records that its in-repository path is now the stated exception (4.1), not the general case |
| `tool-cmakelib.md` | Paths and the component base |
| `tool-neovim.md` NVIM-R-4 | "The install prefix SHALL be the application directory" becomes a directory named after the tool beneath it |
| `tool-cmake.md` CMAKE-R-2 | Reviewed, expected unchanged: "installed under the application directory" stays true at `App/cmake/<version>/` |
| `mise.toml` | `{{config_root}}` prohibited in this file (F-8) |
| `spec-mise-migration.md` §5 | Superseded in place, as GEN-A-6 |

## 6. Verification

| Claim | Check |
|---|---|
| Layout | After setup, each managed tool has exactly one directory under the application directory named after it; the application root contains no `lib64` or `share` |
| Global visibility | An interactive shell started outside this repository resolves every pinned tool by name and reports the pinned version |
| No system fallthrough | The same shell resolves `cmake` to the pinned version, not the system one |
| One version | After a pin bump and a setup run, exactly one version of that tool is installed |
| Containment | Every installed artifact and fetched source resolves under the application directory, except the one member of the 4.1 exception; `_vendor/` does not exist |
| The exception holds | The autosuggestions plugin loads in an interactive shell from its in-repository path (ZSH-R-12, unchanged) |
| No `config_root` | Searching the configuration file for `config_root` returns nothing (F-8) |
| Idempotence | Two consecutive setup runs; the second reports no work and exits zero (GEN-R-4) |
| Pin index | Every key in the registry table resolves in the pin file, and no requirements document restates a pinned value |

## 7. Out of scope

**Migration of existing state.** The tasks fetch and install into the new
locations; they do not remove the old ones. The stale paths
(`App/lib64`, `App/share`, `App/bin/nvim`, `App/mise/installs`, `repo/_vendor`)
are left for the user to remove after verifying the new layout. Nothing reads
them once the change lands, and automatic deletion of paths a previous version
of this repository created is the kind of decision GEN-R-17 exists to refuse.

**The repository's position inside the application directory.** `./setup`
already warns that the repository sits inside `~/App`, which this design does
not change and does not worsen.

## 8. Decisions taken without explicit confirmation

**ohmyzsh moves to `App/ohmyzsh/`.** Asked twice, not answered.

The argument originally offered for moving it - that it makes GEN-R-3 a single
rule - does not survive F-7: `zsh-autosuggestions` cannot move, so the rule
splits either way and the criterion in 4.1 has to be written regardless. What
remains is weaker but still holds: ohmyzsh is ordinary fetched runtime content
under no fixed-path constraint, so leaving it in the repository would make it
the one member of the exception that has not earned it, and would keep
`_vendor/` alive for a single directory.

If it stays, the changes are small and local: `_vendor/` survives, its
`.gitignore` entry stays, the render placeholder keeps pointing into the
repository, and the criterion in 4.1 gains a second member - which then needs
its own recorded justification, because ZSH-A-7 does not cover it.
