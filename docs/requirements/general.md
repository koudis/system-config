# General Requirements

Definitions, assumptions and requirements that apply to **every** managed tool
in this repository. Per-tool documents inherit everything here and only record
what is specific to that tool.

Identifier scheme used across these documents:

| Prefix | Meaning |
|---|---|
| `GEN-D-n` | Definition |
| `GEN-A-n` | Assumption (global) |
| `GEN-R-n` | Requirement (global) |
| `<TOOL>-A-n` | Assumption specific to one tool |
| `<TOOL>-R-n` | Requirement specific to one tool |

Requirement language: **SHALL** is mandatory, **SHOULD** is a strong default
that may be overridden with a recorded reason, **MAY** is optional.

---

## 1. Definitions

**GEN-D-1 Repository root.** The directory containing this repository's `.git`.
All paths in these documents are relative to it unless stated otherwise.

**GEN-D-2 Managed tool.** A unit of configuration with its own lifecycle,
its own requirements document, and its own entry in the orchestrator. A managed
tool is the granularity at which things are added, removed and reasoned about.

**GEN-D-3 Orchestrator.** The single component that decides what runs, in what
order, and whether it needs to run at all. There is exactly one.

**GEN-D-4 Task.** A named unit of work owned by the orchestrator, with declared
predecessors, declared inputs and declared outputs.

**GEN-D-5 Pin.** The exact recorded identity of an external source: a version
tag, a commit SHA, or a content checksum. A branch name is not a pin.

**GEN-D-6 Build input.** An external source that is consumed to produce a
binary and is disposable afterwards. Its working tree carries no state worth
keeping.

**GEN-D-7 Runtime content.** An external source that persists on disk after
setup and is read directly at runtime by a configured program. It is never
compiled.

**GEN-D-8 System package.** Software installed by the operating system's
package manager, machine-global and not version-pinned by this repository.

**GEN-D-9 Dev tool.** A versioned developer binary that this repository pins
and installs itself, independent of the operating system.

**GEN-D-10 Render.** Producing a concrete configuration file from a template by
substituting placeholders with values known only at setup time.

**GEN-D-11 Deploy.** Making a rendered or committed configuration file visible
to a program at the location it expects, by symbolic link.

**GEN-D-12 Containment.** The property that a file lives inside either the
repository root (GEN-D-1) or the application directory (GEN-D-13). These are
the only two locations this repository owns.

**GEN-D-13 Application directory.** The single filesystem location into which
all installed artifacts are placed: compiled binaries, downloaded SDKs, and
orchestrator-managed tool installations. Its default is `~/App`. It is
configurable (GEN-R-1b) and it is not inside the repository.

**GEN-D-14 Installed artifact.** Any binary or SDK produced or fetched by
setup. Installed artifacts are machine-local, disposable, and reproducible from
the pins; they are never committed.

---

## 2. The classification rule

Every external source SHALL be classified as exactly one of GEN-D-6 through
GEN-D-9. The classification is decided by **where the artifact ends up**, not
by how it is obtained:

| The artifact ends up as | Classification | Consequence |
|---|---|---|
| A binary this repo pins and owns | Dev tool | Orchestrator installs it |
| A binary produced by compiling source | Build input | Orchestrator builds it; source is scratch |
| A file read at runtime from disk | Runtime content | Fetched and kept; pinned; never built |
| A binary the OS owns | System package | Declared, installed by OS package manager |

The fact that something is downloaded does not by itself make it runtime
content. A downloaded tarball that is compiled and discarded is a build input.

---

## 3. Global assumptions

Each assumption records its validation status. `VERIFIED` means checked against
an authoritative upstream source or against this machine on 2026-08-15.

**GEN-A-1 Single user, single machine.** One user account, one laptop
configured at a time. No multi-machine divergence, no shared state, no secrets
management. `VERIFIED` - stated requirement.

**GEN-A-2 Fedora only.** Fedora is the sole supported platform. Other
distributions are out of scope: not declared, not tested, not accommodated.
`VERIFIED` - stated requirement. This narrows an earlier position that treated
Debian as a declared-but-untested secondary, and it retires the corresponding
half of the existing operating-system switch.

**GEN-A-3 Network is available during setup.** Every external source is fetched
at setup time. Nothing is vendored into git. There is no offline install path.
`VERIFIED` - true of the current submodule approach also.

**GEN-A-4 No SSH key exists on a fresh machine.** Setup runs before the user has
uploaded a key to any forge. Every source URL SHALL therefore be reachable
anonymously over HTTPS. `VERIFIED` - this is the failure mode of the current
repository, where four sources use SSH URLs.

**GEN-A-5 `sudo` is available and interactive.** System package installation
requires elevation and the user is present to authorise it. `VERIFIED`.

**GEN-A-6 The orchestrator's configuration is found from the repository root.**
Configuration resolution walks upward from the working directory, so a
repository-root configuration file is the native case and no machine-global
configuration participates. `VERIFIED` - upstream configuration documentation.

**GEN-A-7 The tool-install location is fixed before the orchestrator starts.**
The variable controlling where tools are installed is read at process start and
cannot be set from within the orchestrator's own configuration. A wrapper must
export it. `VERIFIED` - upstream environments documentation states this
explicitly.

**GEN-A-8 System-package support in the orchestrator is experimental.** The
declarative system-package subsystem is gated behind an experimental flag and
is mid-rename upstream. The orchestrator's own FAQ additionally states it is
"for dev tools, not applications or system packages", which predates the
feature. This tension is real and unresolved upstream. `VERIFIED - CAVEATED`.
See GEN-R-11.

**GEN-A-9 Flathub is not guaranteed to be configured.** Flatpak itself ships
with Fedora Workstation, but the Flathub remote is opt-in through Third-Party
Repositories, and when enabled that way it may be a *filtered* remote exposing
only a Fedora-approved subset. Adding the remote manually removes the filter.
`VERIFIED` - Flathub Fedora setup page and Fedora `fedora-flathub-remote`
package description.

**GEN-A-10 Compilation prerequisites are not present by default.** A fresh
Fedora installation does not carry the toolchain needed to build the build
inputs. Prerequisites SHALL be declared per tool, not assumed. `VERIFIED` -
see the Neovim document.

---

## 4. Global requirements

### Containment

The repository and the application directory divide cleanly by role. The
repository is the source of truth: configuration, templates, pins and
documentation. The application directory is the install target: everything that
setup produces or downloads as an executable artifact. Neither contains the
other's content.

**GEN-R-1** Every file this repository creates or fetches SHALL be contained
(GEN-D-12), with the sole exception of the symbolic links required by GEN-D-11
and the parent directories those links require.

**GEN-R-1a** All installed artifacts (GEN-D-14) SHALL be placed under the
application directory (GEN-D-13). No installed artifact SHALL be written to any
other location outside the repository. In particular there SHALL NOT be a
second install prefix such as a separate user binary directory.

**GEN-R-1b** The application directory SHALL be configurable through a single
declared setting, SHALL default to `~/App`, and SHALL be referenced everywhere
else by that setting rather than by a literal path. Changing the setting SHALL
be sufficient to relocate every installed artifact.

**GEN-R-1c** Configuration, templates, pins and documentation SHALL live in the
repository and SHALL NOT be placed in the application directory. The two
locations SHALL NOT overlap.

**GEN-R-2** No path in this repository SHALL contain a hardcoded username. Paths
outside the repository SHALL be expressed relative to the user's home directory
or, for installed artifacts, relative to the application-directory setting.

**GEN-R-3** Fetched sources and orchestrator working state SHALL be contained in
the repository but SHALL NOT be committed. Installed artifacts SHALL be
contained in the application directory and SHALL NOT be committed. All are
machine-local and reproducible from the pins.

**GEN-R-3a** The application directory SHALL be reconstructible from an empty
state by a single setup run. Deleting it SHALL NOT lose information that exists
nowhere else.

### Correctness

**GEN-R-4** Every task SHALL be idempotent. Running setup twice in succession
SHALL make no changes on the second run and SHALL NOT fail.

**GEN-R-5** Task ordering SHALL be declared explicitly. Ordering SHALL NOT be
implied by file position, alphabetical naming, or execution sequence.

**GEN-R-6** Every external source SHALL have a pin (GEN-D-5) recorded in the
single pin location (GEN-R-7). Tracking a branch is prohibited.

**GEN-R-7** There SHALL be exactly one file in which version pins are recorded.
Pins SHALL NOT additionally live in shell constants, submodule gitlinks, or
template files.

**GEN-R-8** There SHALL be no operating-system conditionals anywhere. Under
GEN-A-2 there is one target platform, so a branch on the operating system is
by definition dead code. Package names are declared for Fedora only.

**GEN-R-8a** Should a second platform ever be required, it SHALL be introduced
by adding a declaration mechanism in one shared place, never by reintroducing
per-tool conditionals - which is the pattern GEN-A-2 was adopted to remove.

**GEN-R-9** A tool SHALL NOT configure another tool. Any value one tool needs
from another SHALL be an explicitly declared input, not an incidental side
effect of the other tool's setup.

**GEN-R-10** Setup SHALL offer a preview mode that reports what would change
without changing it.

**GEN-R-11** Where the orchestrator's experimental features are used
(GEN-A-8), the affected requirements document SHALL record a fallback approach
that satisfies the same requirements without them.

### Verifiability

**GEN-R-12** Every requirement SHALL be verifiable by an observable check. A
requirement that cannot be checked is a preference and belongs in prose, not in
a numbered requirement.

**GEN-R-13** Every managed tool SHALL have a requirements document in this
directory, named `tool-<name>.md`.

**GEN-R-14** Every package name and prerequisite recorded in these documents
SHALL be sourced from the upstream project or from Fedora's own package index,
not inferred from a binary name.

---

## 5. Verification of the global requirements

| Requirement | Observable check |
|---|---|
| GEN-R-1 | After setup, no file created outside the repository and the application directory except the declared links |
| GEN-R-1a | Every installed binary resolves under the application directory; no second install prefix exists |
| GEN-R-1b | Changing the setting and re-running relocates every artifact; the literal default path appears only in the setting's own definition |
| GEN-R-1c | The application directory contains no templates, pins or documentation |
| GEN-R-2 | Searching the repository for absolute home paths containing a literal username returns nothing |
| GEN-R-3 | The ignore file covers the state, build and vendor directories; the application directory is outside the repository and untracked by construction |
| GEN-R-3a | Deleting the application directory and re-running setup restores a working environment |
| GEN-R-4 | Two consecutive setup runs; the second reports no work and exits zero |
| GEN-R-5 | The orchestrator can print a dependency graph |
| GEN-R-6, GEN-R-7 | Every source in every tool document appears in the single pin file, and nowhere else |
| GEN-R-8 | Searching per-tool definitions for OS conditionals returns nothing |
| GEN-R-9 | Each tool document's declared inputs account for every value it consumes |
| GEN-R-10 | Preview mode runs and changes nothing |
| GEN-R-13 | Every managed tool has a matching document in this directory |

---

## 6. Known defects in the current implementation

Recorded here because they are violations of the requirements above, and each
per-tool document references the ones that affect it.

| Defect | Violates | Location |
|---|---|---|
| Second run fails; link created without replacing, parent directory not created | GEN-R-4 | `kitty/setup.sh` |
| No state tracking; everything re-runs unconditionally | GEN-R-4 | all setup scripts |
| Unreachable error handling: exit status tested after the shell has already aborted | GEN-R-12 | `lib.sh` |
| Nine vendored sources, eight declared; one orphaned | GEN-R-6 | `.gitmodules` |
| Four sources use SSH URLs | GEN-A-4 | `.gitmodules` |
| Pins split across gitlinks, shell constants, and nothing | GEN-R-7 | repository-wide |
| One tool's configuration emitted by another tool's template | GEN-R-9 | cmakelib and zsh |
| Operating-system conditionals repeated per tool, for a platform now out of scope | GEN-R-8 | every `install_deps.sh` |
| Two competing install prefixes: binaries to a user binary directory, SDKs to the application directory | GEN-R-1a | `setup.sh` and `lib.sh` |
| Application directory path hardcoded rather than configurable | GEN-R-1b | `lib.sh` |
| Go SDK path hardcoded to a specific version, never installed, injected into PATH | GEN-R-1b, GEN-R-3a, GEN-R-6 | `lib.sh` |
| Absolute path containing a literal username | GEN-R-2 | `zsh/template/zshrc_template` |
| Package named by binary rather than by package name | GEN-R-14 | `zsh/install_deps.sh` |
| Misspelled package name | GEN-R-14 | `vim/install_deps.sh` |
| Applications installed without ensuring their remote exists | GEN-A-9 | `flatpak/setup.sh` |
