# Tool Requirements: Zsh

Inherits everything in [general.md](general.md).

## 1. Purpose

The login shell, its framework, its theme, and the environment that every other
tool becomes visible through.

## 2. Classification

Mixed, and the parts are deliberately separated:

| Part | Classification |
|---|---|
| `zsh` itself and its helper utilities | System package (GEN-D-8) |
| Oh My Zsh framework | Runtime content (GEN-D-7) |
| Autosuggestions plugin | Runtime content (GEN-D-7) |
| Theme | Repository content, committed |
| Shell configuration | Rendered (GEN-D-10) and deployed (GEN-D-11) |

## 3. Pins

| Source | Pin | Recorded as |
|---|---|---|
| Oh My Zsh | `b54a7197` | commit SHA - there is no tag |
| Autosuggestions | `c3d4e57` (`v0.7.0-12-g...`) | commit SHA |

**ZSH-R-1** Both SHALL be fetched over HTTPS anonymously (GEN-A-4) and pinned by
SHA. Neither may track a branch.

## 4. Oh My Zsh constraints

These are upstream constraints, not preferences.

**ZSH-A-1** Oh My Zsh requires a real repository working tree. Its update check
aborts outright unless the framework directory is a repository, and its
update-availability check reads repository-local configuration for the remote
and branch. `VERIFIED` - upstream update-check source.

**ZSH-R-2** Oh My Zsh SHALL therefore be obtained as a repository clone, **not**
as an archive. An archive install permanently disables updates. Upstream
declined a request to support archive installation on exactly this ground.

**ZSH-A-2** The framework directory must not be group- or world-writable. Loose
permissions make shell completion initialisation fail. `VERIFIED` - upstream
installer sets a restrictive mask for this reason.

**ZSH-R-3** The clone SHALL be created with a restrictive permission mask.

## 5. Theme

**ZSH-R-4** The theme SHALL be a committed file in the framework's custom theme
directory. Patching the fetched framework tree is prohibited: it is not
idempotent, and it breaks whenever upstream moves.

**ZSH-A-3** The custom directory is already configured and already exists for
this purpose, so no new mechanism is required. `VERIFIED` - existing
configuration and directory layout.

## 6. System packages

**ZSH-R-5** Packages SHALL be declared by their Fedora package name, never by
the name of the binary they provide (GEN-R-14):

| Provides | Fedora package |
|---|---|
| Zsh | `zsh` |
| Directory environments | `direnv` |
| Fuzzy finder | `fzf` |
| Silver Searcher (`ag`) | `the_silver_searcher` |

**ZSH-A-4** The current implementation declares `ag`, which is the binary name
and is not a valid Fedora package name. `VERIFIED` - upstream project
installation instructions, which give `the_silver_searcher` for Fedora.

## 7. Login shell

**ZSH-R-6** Setup SHALL make Zsh the login shell without a manual step. The
shell must be registered as a valid login shell before it can be selected.

**ZSH-A-5** The orchestrator can perform both the registration and the change:
it adds the configured shell to the system's list of valid login shells and
then applies the change. `VERIFIED` - orchestrator system-install
documentation. This relies on the experimental subsystem (GEN-A-8); the
fallback under GEN-R-11 is to leave it manual and document it, as today.

## 8. Rendered configuration

**ZSH-R-7** One file is rendered and deployed: the shell configuration itself.

**ZSH-A-6** The secondary fragment this configuration sources today
(`config_template` rendered to `zsh/config` and linked as `~/.zshrc_config`)
holds nothing but cmakelib's two exports and a no-op `PATH` assignment.
`VERIFIED` - the file is five lines long. Declaring those exports where
cmakelib owns them (CMLIB-R-3) empties the fragment completely, so it is
deleted rather than ported.

**ZSH-R-8** Placeholders substituted at render time SHALL be limited to values
genuinely unknown until setup runs. After this change exactly one remains in
this tool: the framework path. The CMake library path leaves with the fragment
(ZSH-A-6), and two path fragments are removed outright (ZSH-R-10, ZSH-R-11).

**ZSH-R-9** The configuration SHALL NOT export another tool's settings
(GEN-R-9). The CMake library's environment currently originates here; it SHALL
be declared as an input from that tool's document rather than emitted as a side
effect of configuring the shell.

**ZSH-R-10** The user binary path fragment SHALL be removed. Tool visibility is
provided by the orchestrator's shell activation, which covers every installed
artifact at once.

**ZSH-R-11** The Go path fragment SHALL be removed for the same reason, and the
Haskell environment line SHALL be deleted outright - see the Go document and
GEN-R-2.

## 9. Verification

| Requirement | Check |
|---|---|
| ZSH-R-2 | The framework's own update command runs without error |
| ZSH-R-3 | The framework directory is not group- or world-writable |
| ZSH-R-4 | The theme loads and no patch file remains in the repository |
| ZSH-R-5 | Every declared package installs on a clean Fedora machine |
| ZSH-R-6 | The login shell is Zsh after setup, with no manual step |
| ZSH-R-9 | The CMake library environment is traceable to that tool's document |
| ZSH-R-11 | No path in the rendered configuration references a missing directory |
