# How to Add a New Tool

The explicit, ordered procedure for bringing a new tool under management in this
repository. Follow every step. Steps 1 and 2 decide almost everything that
follows, so do not skip ahead to installation.

This document contains no code. It describes decisions and artifacts, not
commands.

Terms used here are defined in
[requirements/general.md](requirements/general.md); identifiers such as
`GEN-R-7` refer to numbered requirements there.

---

## Step 0 - Decide whether it is a managed tool at all

Not everything belongs in this repository. A thing is a **managed tool**
(GEN-D-2) only if all of the following hold:

- It must be present for the workstation to be considered set up.
- Its absence or its version actually matters to you.
- It has a lifecycle: it is installed, configured, updated, and possibly
  removed.

If it is a one-off experiment, a project-scoped dependency, or something you
would not miss on a new laptop, do not add it. The cost of a managed tool is a
requirements document that must be kept true.

**If it is not a managed tool, stop here.**

---

## Step 1 - Classify it

This is the single most important decision. Everything downstream follows from
it. Use the rule in general.md section 2: classification is decided by **where
the artifact ends up**, not by how it is obtained.

Answer one question: *what does this leave on disk that something else uses?*

| What it leaves | Classification | Where it lives | Pinned by you? |
|---|---|---|---|
| A binary the operating system owns | System package (GEN-D-8) | OS-controlled | No |
| A binary you pin, installed prebuilt | Dev tool (GEN-D-9) | Application directory | Yes |
| A binary you pin, produced by compiling | Build input (GEN-D-6) | Application directory | Yes |
| A file read from disk at runtime | Runtime content (GEN-D-7) | Repository | Yes |

Two traps:

**A download is not automatically runtime content.** An archive that gets
compiled and thrown away is a build input. Ask what survives, not what arrives.

**Prefer a dev tool over a build input.** Compiling is only justified by a
build-configuration requirement you can state. If you cannot name the flag or
option that forces a source build, take the prebuilt binary. See
[tool-cmake.md](requirements/tool-cmake.md), which is currently misclassified
for exactly this reason, and contrast
[tool-neovim.md](requirements/tool-neovim.md), where a specific build type
genuinely justifies it.

### If it is a desktop application

Graphical end-user applications take a preference order rather than a
classification, because more than one source can supply the same application.
Apply it in order and take the first that works:

1. **Flatpak** - preferred.
2. **Distribution package** (`dnf`) - when no suitable Flatpak exists.
3. **Manual acquisition** - download, and build if necessary.

Apply this **when adding the application**, then record which tier you landed
on. Do not implement it as a runtime fallback chain: a chain means the same
repository produces a different machine depending on what happened to be
reachable, and you cannot tell afterwards which tier supplied what. It would
also not behave as expected - when the Flatpak CLI is missing the orchestrator
*skips* those entries rather than failing, so a fall-through rule would quietly
install nothing.

Tier 3 is not a promise you can make for every application. Some have no
buildable source at all, and some are large desktop applications whose source
build is a project in itself. An application that genuinely needs tier 3 stops
being an entry in a list and becomes a managed tool with its own document -
which means starting this procedure again from Step 1.

See [tool-desktop-apps.md](requirements/tool-desktop-apps.md).

---

## Step 2 - Write the requirements document first

Create `docs/requirements/tool-<name>.md` **before** touching any
configuration. GEN-R-13 makes this mandatory, and it is not bureaucracy: the act
of filling in section 5 below is what surfaces hidden coupling before it gets
built in.

Use this shape, matching the existing documents:

1. **Purpose** - one or two sentences. Why this exists on the machine.
2. **Classification** - from Step 1, with the reasoning.
3. **Pin** - the exact version, tag or commit, and how it is recorded.
4. **Prerequisites** - what must already be present for this to install or
   build.
5. **Declared inputs and outputs** - see Step 5.
6. **Requirements** - numbered `<TOOL>-R-n`, using SHALL/SHOULD/MAY.
7. **Assumptions** - numbered `<TOOL>-A-n`, each with a validation status.
8. **Verification** - an observable check per requirement.

Use [tool-kitty.md](requirements/tool-kitty.md) as the template for a simple
tool and [tool-neovim.md](requirements/tool-neovim.md) for a complex one.

---

## Step 3 - Establish the pin

Unless it is a system package, the tool needs a pin (GEN-D-5).

- A **tag** is acceptable when upstream does not move tags.
- A **commit SHA** is required when there is no usable tag, or when the tag
  could move.
- A **content checksum** is required for downloaded archives and is the
  strongest option.
- A **branch name is never a pin** (GEN-R-6).

Record it in the single pin file and nowhere else (GEN-R-7). Do not put the
version in a template, a script constant, or a directory name. The current
repository's central failure is exactly this: versions split across three
mechanisms that disagree with each other.

**Source URLs must be anonymous HTTPS** (GEN-A-4). A URL requiring an SSH key
breaks the fresh-machine case, which is the only case this repository exists to
serve.

---

## Step 4 - Declare prerequisites, do not assume them

List every system package the tool needs in order to install or build. Take the
names from the upstream project's own documentation or from Fedora's package
index (GEN-R-14).

Two failure modes to avoid, both present in the repository today:

- **Naming a package after its binary.** The Silver Searcher provides `ag` but
  is packaged as `the_silver_searcher`. There is no Fedora package called
  `ag`.
- **Assuming the toolchain is present.** A fresh installation does not carry
  compilers or build utilities (GEN-A-10). Neovim, for instance, needs a
  library package that was split out of the C library several Fedora releases
  ago and is easy to miss.

Do not write an operating-system conditional anywhere (GEN-R-8). Fedora is the
only target, so a branch on the operating system is dead code by construction.
Declare the Fedora package name and nothing else.

---

## Step 5 - Declare inputs and outputs explicitly

This is the step that prevents the repository's worst structural defect.

- **Inputs**: every value the tool consumes that it does not itself define -
  the application directory, a path from another tool, a version from the pin
  file.
- **Outputs**: every value the tool produces that anything else consumes -
  environment variables, installed paths.

**A tool must never configure another tool** (GEN-R-9). If tool A needs a value
from tool B, that value is declared as B's output and A's input. It is not
emitted as a side effect of setting up B, and it is certainly not emitted from
a third tool's template.

The cautionary example is
[tool-cmakelib.md](requirements/tool-cmakelib.md): its own setup step does
nothing, and its environment is emitted from the shell's configuration
template. The coupling exists only in a source comment. Nothing about that is
discoverable from the tool itself.

---

## Step 6 - Place it in the task graph

Add the tool to the orchestrator with its predecessors **declared** (GEN-R-5).
Ordering must never depend on file position, alphabetical naming, or luck.

Ask three questions:

1. What must exist before this runs? Those are its declared predecessors.
2. Does anything need this before *it* runs? Then that thing declares this one.
3. Is it genuinely independent? Then it declares nothing and may run in
   parallel.

Note that "check that a command exists" is not a dependency declaration. It is a
runtime assertion that turns a missing predecessor into a failure instead of
preventing it. The current Neovim step checks that CMake exists rather than
declaring that CMake must be built first, and only works because a system CMake
happens to be installed.

---

## Step 7 - Choose how freshness is decided

For anything expensive - a compile, a large download - decide what makes the
work stale. This is what keeps setup idempotent (GEN-R-4) without re-doing
everything.

**Prefer keying freshness on the pin, not on the source tree.** A build should
re-run when you change the version, which is precisely what a small file
containing the pinned version expresses. Keying on the source tree instead is
worse in three concrete ways: files extracted from archives can carry timestamps
that make the work look permanently stale, scanning a large tree is slow, and
the orchestrator has known open defects around multiple outputs and deleted
inputs. One input, one output, keyed on the version, avoids all of it.

For cheap, safe steps - creating a link, writing a rendered file - freshness
tracking is unnecessary. Make the operation naturally repeatable instead: create
parent directories first, and replace existing targets rather than failing on
them.

---

## Step 8 - Respect the location split

Two locations, no overlap (GEN-R-1a, GEN-R-1c):

- **Repository**: configuration, templates, pins, documentation, and fetched
  runtime content.
- **Application directory**: everything installed - compiled binaries,
  downloaded SDKs, orchestrator-managed tool installations. Configurable,
  defaulting to `~/App` (GEN-R-1b).

Never introduce a second install prefix. Never reference the application
directory by literal path; reference the setting. Never place a template or a
pin inside the application directory.

Deleting the application directory and re-running setup must restore a working
environment (GEN-R-3a). If your tool would lose something in that scenario, it
is storing state in the wrong place.

---

## Step 9 - Verify

Every requirement needs an observable check (GEN-R-12). A requirement you cannot
check is a preference; move it to prose.

At minimum, confirm:

- Setup runs twice in succession with no changes and no failure on the second
  run.
- The tool works from a genuinely clean state, not just from your machine.
- Every path the tool adds to the environment actually exists.
- No literal username and no hardcoded application-directory path was
  introduced.

The clean-state check matters more than it sounds. Most defects in this
repository are invisible on a configured machine and only appear on a fresh one:
the missing Flathub remote, the SSH-only sources, the dangling Go path, the
terminal configuration directory that does not exist yet.

---

## Checklist

Copy this into the pull request or commit message.

- [ ] Step 0 - Confirmed it is genuinely a managed tool
- [ ] Step 1 - Classified, with the reasoning recorded
- [ ] Step 2 - `docs/requirements/tool-<name>.md` written
- [ ] Step 3 - Pinned by tag, SHA or checksum, in the single pin file only
- [ ] Step 3 - Source URL is anonymous HTTPS
- [ ] Step 4 - Prerequisites declared with real Fedora package names
- [ ] Step 4 - No operating-system conditional anywhere
- [ ] Step 5 - Inputs and outputs declared; nothing configured by another tool
- [ ] Step 6 - Predecessors declared, not asserted at runtime
- [ ] Step 7 - Freshness keyed on the pin for expensive work
- [ ] Step 8 - Installs to the application directory via the setting
- [ ] Step 9 - Two consecutive runs clean; verified from a clean state
- [ ] `docs/requirements/README.md` index updated

---

## Removing a tool

The reverse, in order: delete its entry from the orchestrator, delete its pin,
delete its prerequisites if nothing else declares them, delete any inputs other
tools took from it, delete its deployed links, then delete its requirements
document. Check that no other document still cites its identifiers.

Leaving a stale requirements document behind is worse than leaving stale code -
the code merely does nothing, whereas the document asserts something untrue.
