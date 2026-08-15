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
| Version | v0.11.6 |
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

**NVIM-R-4** The install prefix SHALL be the application directory (GEN-R-1a).

**NVIM-A-4** Building from a release tarball rather than a repository produces
the correct version string at a release tag. The version generator falls back
to the declared version when the repository query fails, and at a release tag
that fallback is already correct. `VERIFIED` - upstream version-generation
logic.

**NVIM-A-5** The historical failure mode for tarball builds was a release
tarball extracted *inside another repository*, which is exactly this layout.
That was corrected upstream and backported to 0.8, so v0.11.6 is unaffected.
`VERIFIED` - upstream change and its backport.

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
| NVIM-R-4 | The binary resolves under the application directory |
| NVIM-A-4 | Reported version is exactly `v0.11.6`, with no development suffix |
| NVIM-R-5 | The build succeeds on a machine with no system CMake installed |
| NVIM-R-8 | The provider package is installed and the editor reports Python support |
