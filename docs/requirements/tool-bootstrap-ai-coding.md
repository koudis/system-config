# Tool Requirements: bootstrap-ai-coding

Inherits everything in [general.md](general.md).

## 1. Purpose

`bac` provisions a disposable Docker container per project for AI-assisted
coding sessions. The agent credential stores already present on the host are
bind-mounted into the container, so a session needs no second login, and an SSH
server inside the container is what an editor connects to.

The binary is named `bac`; the project is named `bootstrap-ai-coding`. This
document uses the project name, and the installed directory uses the binary
name, the same way the editor document is `tool-neovim.md` while the directory
is `nvim`.

## 2. Classification

**Build input** (GEN-D-6). The source tree is fetched, compiled with the pinned
Go toolchain, and is scratch afterwards. The resulting binary is an installed
artifact (GEN-D-14) and lives under the application directory (GEN-D-13).

**BAC-A-1** A **dev tool** (GEN-D-9) classification was available and is the one
[adding-a-new-tool.md](../adding-a-new-tool.md) Step 1 prefers: upstream
publishes prebuilt static `linux/amd64` and `linux/arm64` binaries as release
assets. It was rejected deliberately. Upstream publishes no checksum beside
those assets, so the strongest pin available for them (GEN-D-5) would be one
this repository computed for itself and would then have to maintain, whereas a
tag names what upstream itself published. Compiling introduces no new
prerequisite: the Go toolchain is already a pinned dev tool and the build needs
nothing else this repository does not already declare. `VERIFIED` - release
asset list for the pinned tag, read from the upstream release index on
2026-08-20.

## 3. Pin

| Property | Value |
|---|---|
| Version | recorded in the pin registry (GEN-D-16) under key `BAC_REF` |
| Mechanism | git tag, checked out by the fetch step |
| Source URL | anonymous HTTPS (GEN-A-4) |

**BAC-R-1** The pin SHALL be recorded once, as the `BAC_REF` key in the pin
registry, and SHALL NOT be restated in a task body, a template, or a directory
name (GEN-R-7).

**BAC-A-2** The pinned tag names a fixed commit and upstream does not move it.
Release tags there are outputs of a release that also published binaries, not
moving pointers, and the repository is under the same ownership as this one.
`VERIFIED` - the upstream tag list was read on 2026-08-20 and the pinned tag
resolves to a single commit. Should that ever stop holding, GEN-R-6 requires
the key to hold the commit instead; that is a change of value, not of
structure.

**BAC-A-3** The build records the pin into the binary without this repository
restating it. Upstream's release recipe derives its version string from
`git describe` against the checkout and injects it at link time, so a checkout
at the pinned tag produces a binary that reports exactly that tag. `VERIFIED` -
built from a checkout at the pinned tag on 2026-08-20; the binary reports the
tag verbatim.

## 4. Build prerequisites

**BAC-R-2** The build SHALL require only prerequisites this repository already
declares for other tools: the pinned Go toolchain (see
[tool-go.md](tool-go.md)), `git`, and `make`. It SHALL NOT introduce a new
Fedora package name.

**BAC-A-4** No C toolchain is required. Upstream's release recipe sets
`CGO_ENABLED=0` and links statically, so the build does not reach for a
compiler even though one is present for the editor's sake. `VERIFIED` -
upstream build recipe, and a build performed on 2026-08-20.

**BAC-A-5** The module declares Go 1.25.0 as its minimum, which the pinned
toolchain satisfies. `VERIFIED` - upstream module file and upstream's own
build instructions, which state Go 1.25 or newer.

**BAC-A-6** The build downloads its Go module dependencies from the network. It
is not offline, and those dependencies are pinned by upstream's own module
checksum file rather than by this repository. `VERIFIED` - upstream module and
checksum files.

## 5. Runtime prerequisites

These are required to *run* `bac`, never to build it. None of them gates the
build, and none of them belongs in the preflight command list, which gates only
what the unprivileged tasks themselves execute.

**BAC-R-3** A Docker Engine API endpoint reporting version 20.10 or newer SHALL
be treated as an **external runtime prerequisite**: recorded here and in the
repository README, and neither installed nor configured by setup.

**BAC-A-7** `bac` locates the daemon through the standard Docker environment,
pings it, and refuses to continue when the reported server version is older
than 20.10. It fails with its own message naming the cause, so setup needs no
guard of its own for the absent case (GEN-R-8b covers guards for commands setup
itself executes, which this is not). `VERIFIED` - upstream client code for the
pinned tag.

**BAC-A-8** Fedora's own engine package, `moby-engine`, **conflicts** with the
`docker-ce` packages from upstream Docker's repository: both provide `docker`,
and a transaction installing one while the other is present cannot be resolved
without erasing it. Declaring the Fedora package as a system prerequisite
(GEN-D-8) would therefore make the privileged phase fail on any machine already
running Docker CE, and would offer to remove a working container engine on the
machine this repository configures. That is the class of decision GEN-R-17
exists to refuse, so no engine package is declared at all. `VERIFIED` -
resolved as a no-op transaction against Fedora 44 on 2026-08-20, on a machine
carrying `docker-ce`; the resolver reported the conflict and named
`--allowerasing` as the only way through.

**BAC-A-9** Supplying the engine from Docker's own repository is not an option
this repository can take either: it would require adding a third-party package
repository, which nothing here does and for which the orchestrator's
declarative package table offers no mechanism. `VERIFIED` - the package table
declares distribution packages only.

**BAC-R-4** Setup SHALL NOT enable the container-engine service and SHALL NOT
change group membership. Both are machine-state changes beyond installing a
package: membership of the `docker` group is equivalent to root on the machine,
and it takes effect only on the next login, so a setup run that granted it
would report success while the shell that ran it still could not use it. They
are recorded as one-time manual steps in the README instead.

**BAC-R-5** An SSH key pair SHALL be treated as an external runtime
prerequisite. `bac` reads an existing public key and does not create one; a key
pair is user identity, not an installed artifact, and generating one on the
user's behalf is not setup's decision to make.

## 6. Declared inputs and outputs

| Input | Source |
|---|---|
| Application directory | global setting (GEN-R-1b) |
| Go toolchain | [tool-go.md](tool-go.md); must be installed before this builds |
| Pinned ref | pin registry key `BAC_REF` |

| Output | Consumer |
|---|---|
| `<application directory>/bac/bin/bac` | the user, through the login profile |
| `<application directory>/bac/bin` | the search-path export in the rendered login profile |

**BAC-R-6** This tool SHALL NOT configure another tool, and no other tool SHALL
configure it (GEN-R-9). Its per-project state lives in its own directory under
the user's configuration directory; that directory belongs to `bac`, not to
this repository, and setup neither creates, reads, nor removes it.

## 7. Layout, fetch and freshness

**BAC-R-7** The tool SHALL own exactly one directory beneath the application
directory (GEN-R-1a), holding the source checkout and the installed binary in
separate subdirectories: `<application directory>/bac/src` and
`<application directory>/bac/bin`. The application root SHALL gain nothing else.

**BAC-R-8** The source SHALL be fetched by the same guarded fetch step every
other pinned checkout uses, so it inherits GEN-R-17a unchanged: a registered
submodule, a work tree with uncommitted changes, or unregistered content at the
target path stops the task by name instead of being replaced.

**BAC-A-10** The build writes its outputs into the source checkout, and
upstream's own ignore rules cover them, so the checkout stays clean afterwards.
This is what keeps BAC-R-8 workable across a pin bump: a dirty checkout would
be refused by the very guard that protects it. `VERIFIED` - upstream ignore
rules, and a build performed on 2026-08-20 after which the checkout reported no
modifications.

**BAC-R-9** Build freshness SHALL be keyed on a version stamp holding the
pinned ref and the application directory, with that stamp as the build's only
declared input and the installed binary as its only declared output
(GEN-R-18) - the same shape, and for the same reasons, as the editor build
(NVIM-R-9).

**BAC-R-10** The stamp SHALL be written by a separate step that always runs and
that the build declares as a predecessor, not from inside the build itself
(GEN-R-18). A stamp written inside the gated body cannot invalidate the gate
that guards it.

**BAC-R-11** The build SHALL invoke upstream's own release recipe rather than
restating the compile command. The link-time flags that inject the version
(BAC-A-3) are upstream's to change; restating them here would create a second
copy that goes stale silently, and the failure would be a binary that
misreports its own version rather than a build error.

**BAC-A-11** That recipe cross-compiles for both `linux/amd64` and
`linux/arm64`. Only the host architecture's output is installed; the other is
left in the scratch checkout and never read. The cost is one redundant
compilation of a statically linked Go program, which is the price of not
restating upstream's build configuration. `VERIFIED` - upstream build recipe,
and a build performed on 2026-08-20.

**BAC-A-12** The recipe invokes a bare `go`, and BAC-R-11 forbids reaching past
it, so the pinned toolchain has to be reachable by name. The orchestrator puts
the bin directory of every tool declared in its tool table on the path it hands
a task, which is what makes the bare name resolve to the pinned toolchain
rather than to a system one. This is the same mechanism the editor build relies
on to find CMake; the difference is that the editor build can name the path
explicitly and this one cannot. `VERIFIED` - observed against mise 2026.8.6
while implementing the editor build, and the harness image carries no system Go
for the bare name to resolve to instead.

**BAC-R-12** The installed binary SHALL be selected by the architecture the Go
toolchain reports, not by a literal architecture name. A machine whose
architecture upstream does not build for SHALL fail the task by naming the
missing file, rather than installing something else.

## 8. Search path

**BAC-R-13** The binary directory SHALL be named in this repository's own
search-path export in the rendered login profile, alongside the orchestrator's
and the editor's. Like the editor, this tool is built from source and is never
resolved as an orchestrator-managed tool, so orchestrator activation does not
expose it and a path entry is the only thing that does.

## 9. Verification

| Requirement | Check |
|---|---|
| BAC-R-1 | The pinned value appears in the pin registry and in no requirements document |
| BAC-A-2 | The source checkout's head resolves to the same commit as the pinned ref |
| BAC-A-3 | The binary reports exactly the pinned ref, read from the pin registry rather than restated |
| BAC-R-2 | The build succeeds in the unprivileged harness image, which carries no prerequisite this repository does not declare |
| BAC-R-3, BAC-A-7 | The build and the harness both complete on a machine with no container engine present |
| BAC-R-7 | The binary resolves at `<application directory>/bac/bin/bac`, and the source checkout at `<application directory>/bac/src` |
| BAC-A-10 | The source checkout reports no modifications after a build |
| BAC-R-9, BAC-R-10 | The stamp's two lines equal the current pinned ref and the current application directory; a second run with the pin unchanged skips the build |
| BAC-R-11, BAC-A-3 | The reported version is the tag, which only the upstream recipe's link-time injection produces |
| BAC-R-13 | The rendered login profile's own search-path export names the binary directory, and it exists |
