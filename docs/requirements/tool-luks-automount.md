# Tool Requirements: luks-automount

Inherits everything in [general.md](general.md).

## 1. Purpose

`luks-automount` unlocks and mounts LUKS-encrypted removable disks when they
are plugged in, taking their passphrases from the session keyring. It runs as a
user service and reaches the privileged operations it needs through a
short-lived worker process rather than by running as root itself.

The binary and the project share the name, so the installed directory is named
after both.

## 2. Classification

**Build input** (GEN-D-6). The source tree is fetched, compiled with the pinned
Go toolchain, and is scratch afterwards. The resulting binary is an installed
artifact (GEN-D-14) and lives under the application directory (GEN-D-13).

**LUKS-A-1** A **dev tool** (GEN-D-9) classification, which
[adding-a-new-tool.md](../adding-a-new-tool.md) Step 1 prefers, was not
available: upstream publishes no release assets at all, only tags, so there is
no prebuilt binary to take and no checksum to pin one by. Compiling introduces
no new prerequisite - the Go toolchain is already a pinned dev tool.
`VERIFIED` - the upstream release index was read on 2026-08-21 and lists no
published assets for the pinned tag.

**LUKS-A-2** This tool is a **partial** build input, and the distinction is the
whole of its design. What setup produces is a *staged* binary. The operational
copy - the one the systemd unit starts and the one the sudoers rule names -
is placed by upstream's own `install` subcommand at a fixed system path, and
that step is not setup's to take (LUKS-R-3). `VERIFIED` - upstream's installer
source for the pinned tag names the fixed path and requests elevation for it.

## 3. Pin

| Property | Value |
|---|---|
| Version | recorded in the pin registry (GEN-D-16) under key `LUKS_REF` |
| Mechanism | git tag, checked out by the fetch step |
| Source URL | anonymous HTTPS (GEN-A-4) |

**LUKS-R-1** The pin SHALL be recorded once, as the `LUKS_REF` key in the pin
registry, and SHALL NOT be restated in a task body, a template, a directory
name, or this document (GEN-R-7, GEN-R-20).

**LUKS-A-3** The pinned tag names a fixed commit and upstream does not move it.
The repository is under the same ownership as this one. `VERIFIED` - the
upstream tag list was read on 2026-08-21 and the pinned tag resolves to a
single commit. Should that stop holding, GEN-R-6 requires the key to hold the
commit instead; that is a change of value, not of structure.

**LUKS-A-4** The binary cannot report its own version, so the pin is not
recoverable from the installed artifact. Upstream's root command declares no
version and its release recipe computes a version string that its link flags
never inject. The version stamp (LUKS-R-9) is therefore the only record of what
the staged binary was built from, and the notice (LUKS-R-4) compares content
rather than versions because content is the only thing there is to compare.
`VERIFIED` - upstream's root command and build recipe for the pinned tag, read
on 2026-08-21.

## 4. Build prerequisites

**LUKS-R-2** The build SHALL require only prerequisites this repository already
declares for other tools: the pinned Go toolchain (see [tool-go.md](tool-go.md))
and `git`. It SHALL NOT introduce a new Fedora package name for the build.

**LUKS-A-5** No C toolchain is required. Every module dependency is pure Go.
`VERIFIED` - upstream module file for the pinned tag, and a build performed in
the unprivileged harness image, which carries a compiler for the editor's sake
but no system Go for a bare `go` to resolve to instead.

**LUKS-A-6** The module declares a minimum Go version that the pinned toolchain
satisfies. `VERIFIED` - upstream module file, read on 2026-08-21, against the
toolchain named in the pin registry.

**LUKS-A-7** The build downloads its Go module dependencies from the network. It
is not offline, and those dependencies are pinned by upstream's own module
checksum file rather than by this repository. `VERIFIED` - upstream module and
checksum files.

## 5. Runtime prerequisites

These are required to *run* `luks-automount`, never to build it. None gates the
build, and none belongs in the preflight command list, which gates only what the
unprivileged tasks themselves execute.

**LUKS-R-2a** `cryptsetup` and `gnome-keyring` SHALL be declared as system
packages (GEN-D-8) in the privileged phase. Both are ordinary distribution
packages: neither conflicts with anything this repository installs and neither
grants privilege, so the reasoning that keeps the container engine undeclared
(BAC-A-8) does not apply to them.

**LUKS-R-3** Upstream's `install` subcommand SHALL be treated as an **external
one-time step**: recorded here and in the repository README, named by setup at
the moment it is needed (LUKS-R-4), and never executed by setup. It writes a
binary to a fixed system path, a `NOPASSWD` sudoers rule naming that path, and a
systemd user unit - three paths outside the application directory, two of them
requiring elevation.

**LUKS-A-8** Running it from setup is not merely disallowed by GEN-R-19, it is
not orderable. The privileged phase runs once per machine and runs first; the
binary it would install does not exist until the unprivileged phase has compiled
it. `VERIFIED` - the phase split and its ordering are stated in GEN-R-19 and
implemented in the orchestrator's `system` task.

**LUKS-R-4** After staging the binary, setup SHALL compare it with the copy at
the fixed system path and, when the two differ or the system copy is absent,
SHALL print the exact command that reconciles them. It SHALL print nothing when
they are identical, and SHALL exit zero in every case. A fresh machine has not
run the one-time step by construction; failing there would make setup fail on
the machine it exists to configure.

**LUKS-R-5** Setup SHALL NOT create the sudoers rule, SHALL NOT enable or start
the user service, and SHALL NOT create mount points. The sudoers rule grants
passwordless root execution of a specific binary; that is a machine-wide
privilege decision of the same class as group membership (BAC-R-4), and this
repository does not take those on the user's behalf.

**LUKS-R-6** Registered disks, their mount points, and their passphrases SHALL
be treated as machine-local state outside this repository's scope. They are
secrets and user identity, not installed artifacts, and GEN-R-3a does not
extend to them: deleting the application directory loses nothing that exists
only there.

## 6. Declared inputs and outputs

| Input | Source |
|---|---|
| Application directory | global setting (GEN-R-1b) |
| Go toolchain | [tool-go.md](tool-go.md); must be installed before this builds |
| Pinned ref | pin registry key `LUKS_REF` |

| Output | Consumer |
|---|---|
| `<application directory>/luks-automount/bin/luks-automount` | the user, once, by absolute path, as named by the notice |
| the notice's text | the user |

**LUKS-R-7** This tool SHALL NOT configure another tool, and no other tool SHALL
configure it (GEN-R-9). Its configuration file lives under the user's
configuration directory; that file belongs to `luks-automount`, not to this
repository, and setup neither creates, reads, nor removes it.

**LUKS-R-8** The binary directory SHALL NOT be added to this repository's
search-path export. This is a deliberate divergence from the editor's and the
session tool's treatment (BAC-R-13). The operational copy of this binary lives
at a fixed system path that is already on the default search path; adding the
staging directory ahead of it would make the bare name resolve to a binary that
is not the one the service and the sudoers rule execute. One name, two
different binaries, is the ambiguity GEN-R-21 exists to prevent.

## 7. Layout, fetch and freshness

**LUKS-R-9** The tool SHALL own exactly one directory beneath the application
directory (GEN-R-1a), holding the source checkout and the staged binary in
separate subdirectories: `<application directory>/luks-automount/src` and
`<application directory>/luks-automount/bin`. The application root SHALL gain
nothing else.

**LUKS-R-10** The source SHALL be fetched by the same guarded fetch step every
other pinned checkout uses, so it inherits GEN-R-17a unchanged: a registered
submodule, a work tree with uncommitted changes, or unregistered content at the
target path stops the task by name instead of being replaced.

**LUKS-R-11** The build SHALL invoke upstream's own documented build command
rather than its release recipe. The recipe writes an output whose name upstream's
ignore rules do not cover, which would leave the checkout dirty and make the next
pin bump refuse itself through the very guard LUKS-R-10 relies on; it also fixes
a single architecture inside the recipe line, where the documented command builds
for the host. Nothing is lost by not using it, because it injects no version
string (LUKS-A-4).

**LUKS-A-9** The documented build command writes an output whose name upstream's
ignore rules do cover, so the checkout stays clean afterwards. This is what keeps
LUKS-R-10 workable across a pin bump. `VERIFIED` - upstream's ignore rules and
build documentation for the pinned tag, read on 2026-08-21.

**LUKS-R-12** Build freshness SHALL be keyed on a version stamp holding the
pinned ref and the application directory, with that stamp as the build's only
declared input and the staged binary as its only declared output (GEN-R-18) -
the same shape, and for the same reasons, as the editor build (NVIM-R-9). The
stamp SHALL be written by a separate step that always runs and that the build
declares as a predecessor. The notice (LUKS-R-4) SHALL likewise be a separate
step that always runs, because a gated build that is skipped cannot print
anything.

## 8. Verification

| Requirement | Check |
|---|---|
| LUKS-R-1 | The pinned value appears in the pin registry and in no requirements document |
| LUKS-A-3 | The source checkout's head resolves to the same commit as the pinned ref |
| LUKS-A-4 | No check asserts a version; the stamp is asserted against the pin registry instead |
| LUKS-R-2, LUKS-A-5 | The build succeeds in the unprivileged harness image, which carries no prerequisite this repository does not declare and no system Go |
| LUKS-R-2a | Both packages are installed after the privileged phase |
| LUKS-R-3, LUKS-A-8, LUKS-R-5 | After a full unprivileged run, the fixed system path, the sudoers path and the user unit path all remain absent |
| LUKS-R-4 | With the system copy absent, the notice names the staged binary's absolute path followed by the install subcommand, and the task exits zero. The differing and identical branches are verified on a real machine, not in the harness: the fixed path is root-owned and the unprivileged image has no elevation with which to stage them |
| LUKS-R-6, LUKS-R-7 | After a full unprivileged run, this tool's configuration directory under the user's configuration directory does not exist, and no template or task body outside this tool's own tasks names it |
| LUKS-R-8 | The bare binary name does not resolve after a full unprivileged run |
| LUKS-R-9 | The staged binary resolves at `<application directory>/luks-automount/bin/luks-automount`, and the source checkout at `<application directory>/luks-automount/src` |
| LUKS-R-10 | The checkout is created by the shared fetch step, so GEN-R-17a's own verification row covers its guards; no second fetch path exists for this tool |
| LUKS-A-9, LUKS-R-11 | The source checkout reports no modifications after a build |
| LUKS-R-12 | The stamp's two lines equal the current pinned ref and the current application directory; a second run with the pin unchanged skips the build and still prints the notice |
