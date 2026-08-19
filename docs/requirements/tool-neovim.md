# Tool Requirements: Neovim

Inherits everything in [general.md](general.md).

## 1. Purpose

The editor. Built from source because a non-default build type is required.

## 2. Classification

**Build input** (GEN-D-6). The source tree is fetched, compiled, and is scratch
afterwards. The resulting binary is an installed artifact (GEN-D-14) and lives
under the application directory (GEN-D-13).

## 3. Pin

| Property | Value |
|---|---|
| Version | recorded in the pin registry (GEN-D-16) under key `NVIM_VERSION` |
| Current pin mechanism | submodule gitlink plus a shell constant, in disagreement |
| Required pin mechanism | release tarball verified by checksum |

**NVIM-A-1** The gitlink is not the effective pin today. The shell constant
decides which tag is checked out, and the build is wrapped in a working-tree
clean on both sides, so the submodule contributes nothing but download volume.
`VERIFIED` - read from the current setup script.

## 4. Build prerequisites

**NVIM-R-1** The following system packages SHALL be declared as prerequisites on
Fedora, taken verbatim from the upstream build documentation:

`ninja-build`, `cmake`, `gcc`, `make`, `gettext`, `curl`, `glibc-gconv-extra`,
`git`

**NVIM-A-2** `glibc-gconv-extra` is required and is the non-obvious one. It was
split out of glibc from Fedora 35 onward; without it the build fails during
message-catalogue generation with character-set errors. `VERIFIED` - upstream
build documentation and the upstream issue that caused it to be added.

**NVIM-A-3** Third-party dependencies (libuv, LuaJIT and others) are downloaded
by the build itself into a subdirectory of the source tree. They are not
declared here and are not separately pinned by this repository. `VERIFIED` -
upstream build documentation.

**NVIM-R-2** The current implementation checks only that a few commands exist
and installs none of the above. This SHALL be corrected: prerequisites are
declared and installed, not assumed.

## 5. Build configuration

**NVIM-R-3** The build type SHALL be `RelWithDebInfo`. This is the reason the
tool is built rather than installed as a prebuilt binary; if the requirement is
ever dropped, this tool SHOULD be reclassified as a dev tool (GEN-D-9).

**NVIM-R-4** The install prefix SHALL be a directory named after the tool
beneath the application directory (GEN-R-1a), not the application directory
itself. Using the root as the prefix writes `bin/`, `lib64/` and `share/`
into it, which is what the one-directory-per-tool rule exists to prevent.

**NVIM-A-4** Building from a release tarball rather than a repository produces
the correct version string at a release tag. The version generator falls back
to the declared version when the repository query fails, and at a release tag
that fallback is already correct. `VERIFIED` - upstream version-generation
logic.

**NVIM-A-5** The historical failure mode for tarball builds was a release
tarball extracted *inside another repository*, which is exactly this layout.
That was corrected upstream and backported to 0.8, so the pinned version is
unaffected. `VERIFIED` - upstream change and its backport.

**NVIM-R-9** Build freshness SHALL be keyed on a version stamp holding the
pinned version and the install prefix, with that stamp as the build's only
declared input and the installed binary as its only declared output.

**NVIM-R-10** The stamp SHALL be written by a separate step that always runs
and that the build declares as a predecessor, not from inside the build itself
(GEN-R-18, GEN-A-12). A stamp written inside the gated body cannot invalidate
the gate that guards it, so a version bump would never rebuild. Because the
stamp's content is a pure function of the pinned version and the prefix, an
unchanged pin reproduces the same bytes and the build is still correctly
skipped.

**NVIM-A-7** A change of install prefix invalidates the build twice over: the
prefix is part of the stamp, and the declared output is expressed in terms of
the prefix, so a new prefix names a path that does not yet exist. `VERIFIED` -
observed while implementing the build task. Upstream also requires a clean
build directory whenever the install prefix changes, which is why the prefix
belongs in the stamp at all.

## 6. Declared inputs

| Input | Source |
|---|---|
| Application directory | global setting (GEN-R-1b) |
| CMake | the CMake tool document; must be available before this builds |
| Repository base path | used when rendering the editor configuration |

**NVIM-R-5** The build SHALL locate CMake by an explicit path, not by searching
the executable path. On a first run the application directory is not yet on the
path, so a bare command name resolves to a system CMake if one exists and fails
otherwise. The current implementation depends on this accident.

## 7. Configuration and plugins

**NVIM-R-6** The editor configuration is rendered from a template
(GEN-D-10) and deployed by symbolic link (GEN-D-11).

**NVIM-R-7** Editor plugins are out of scope. They are managed by the editor's
own plugin manager against its own lockfile, into a directory that is ignored by
this repository. This is a deliberate exclusion, not an omission: it keeps the
plugin edit-test loop independent of setup.

## 8. System package

**NVIM-R-8** The Python provider package SHALL be declared by its correct
Fedora package name: `python3-neovim`.

**NVIM-A-6** The current implementation declares `python-neovim`, which is the
source-package name rather than the installable binary subpackage
`python3-neovim`. `VERIFIED` - Fedora package index. (The same step also
carried a misspelled package name for a second distribution; that line is
removed outright under GEN-A-2.)

## 9. Verification

| Requirement | Check |
|---|---|
| NVIM-R-3 | Reported build type is `RelWithDebInfo` |
| NVIM-R-4 | The binary resolves at `<application directory>/nvim/bin/nvim`, and the application root contains no `lib64` or `share/nvim` |
| NVIM-A-4 | Reported version is exactly the pinned version (registry key `NVIM_VERSION`), with no development suffix |
| NVIM-R-5 | The build succeeds on a machine with no system CMake installed |
| NVIM-R-8 | The provider package is installed and the editor reports Python support |
| NVIM-R-9 | The build declares exactly one input and one output |
| NVIM-R-10 | A second run with the pin unchanged reports the build as up to date and skips it; changing the pinned version and re-running rebuilds, and changing it back rebuilds again |
