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
| Oh My Zsh | recorded in the pin registry (GEN-D-16) under key `OHMYZSH_REF` | commit SHA - there is no tag |
| Autosuggestions | recorded in the pin registry (GEN-D-16) under key `AUTOSUGGEST_REF` | commit SHA |

**ZSH-R-1** Both SHALL be fetched over HTTPS anonymously (GEN-A-4) and pinned by
SHA. Neither may track a branch.

**ZSH-A-7 Oh My Zsh resolves custom plugins only under its custom plugin
directory.** A plugin named in the plugin list is searched for under
`$ZSH_CUSTOM/plugins/<name>` and under the framework's own bundled plugin
directory, and nowhere else. `VERIFIED` - upstream plugin loading, confirmed by
the plugin failing to load from any other location.

**ZSH-R-12** The autosuggestions plugin SHALL therefore be fetched directly to
`zsh/custom/plugins/zsh-autosuggestions`, its real load path, and SHALL NOT be
placed under `_vendor/` with a symbolic link pointing at it. This is a
correction to an earlier formulation that grouped it with the other fetched
runtime content under `_vendor/`; the intent of that formulation - fetched
runtime content lives inside the repository and is never committed - is
unchanged, and the path is ignored by git like the rest of it.

As of 2026-08-17 this path is the single stated exception to GEN-R-3 rather
than an instance of its general case: every other fetched source now lives in
the application directory.

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
directory, extracted once from the pinned framework checkout with the single
change the retired patch made, and committed as the result. Patching the
fetched framework tree at setup time is prohibited: it is not idempotent, and
it breaks whenever upstream moves. The retired patch file is deleted, so the
committed theme is the only copy of that change.

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
then applies the change. The declaration is the `login_shell` key of the
`[bootstrap.user]` table, and it is applied by `mise bootstrap user apply`;
neither a `system` table nor a `system` subcommand exists in the pinned release
(GEN-A-8). `VERIFIED` - observed against mise 2026.8.6. This relies on
the experimental subsystem; the fallback under GEN-R-11 is to leave it manual
and document it, as today.

**ZSH-A-8 The login shell must be declared as an absolute path, and applying it
needs elevation with the search path forwarded.** The orchestrator rejects the
bare name `zsh` and accepts `/usr/bin/zsh`. Applying the change requires
elevation because the underlying `chsh` authenticates the target user through
PAM, which blocks on a password prompt for a non-root caller; and the elevation
must forward the search path explicitly, because `sudo`'s `secure_path` drops
the application directory's binary directory and the orchestrator would not be
found. The applied form is therefore
`sudo env "PATH=$PATH" mise bootstrap user apply --yes`. `VERIFIED` - observed
against mise 2026.8.6 and against the container harness, where a second run
reports the login shell as already set.

**ZSH-A-9** Applying the login shell is unconditional on each run, so it asks
for elevation every run even when nothing changes. This is a known cost, not a
defect in the requirement: the apply itself is a no-op the second time.
`VERIFIED` - observed in two consecutive harness runs.

The elevation is confined to the privileged phase (GEN-R-19), so this cost
applies to `./setup system` only and not to the default `./setup`.

## 8. Rendered configuration

**ZSH-R-7** One file is rendered and deployed: the shell configuration itself.

**ZSH-A-6** The secondary fragment this configuration sources today
(`config_template` rendered to `zsh/config` and linked as `~/.zshrc_config`)
holds nothing but cmakelib's two exports and a no-op `PATH` assignment.
`VERIFIED` - the file is five lines long. Declaring those exports where
cmakelib owns them (CMLIB-R-3) empties the fragment completely, so it is
deleted rather than ported.

**ZSH-R-8** Placeholders substituted at render time SHALL be limited to values
genuinely unknown until setup runs. Three remain in this tool: the framework
path, the custom directory (ZSH-R-14) and the global configuration file
(ZSH-R-15). The CMake library path leaves with the fragment (ZSH-A-6), and two
path fragments are removed outright (ZSH-R-10, ZSH-R-11).

**ZSH-R-14** The custom directory SHALL have its own placeholder,
`___ZSH_CUSTOM_DIR___`, distinct from the framework-path placeholder and from
the global configuration file placeholder (ZSH-R-15). The three name unrelated
values - the framework is fetched runtime content outside the committed tree,
the custom directory is committed repository content, and the configuration
file is this repository's own `mise.toml`, reached by a second route - and a
single placeholder cannot yield all three.

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

**ZSH-R-13** The rendered configuration SHALL export the application
directory, the orchestrator's data directory, the orchestrator's installs
directory, the search path and the global configuration file (ZSH-R-15)
**before** activating the orchestrator, in that order. The data directory and
the installs directory are read at process start (GEN-A-7, GEN-A-11), so
activation that happens first uses the orchestrator's default locations and
every tool an interactive shell installs from then on lands outside the
application directory, breaking GEN-R-1a. The rendered profile is therefore
the second legitimate exporter of those variables beside the entry point
(GEN-R-16), not a duplication of it.

**ZSH-R-13a** Activation SHALL be guarded on the orchestrator's existence
(GEN-R-8b). Before the first setup run the orchestrator is absent, and an
unguarded activation reports an error on every shell start - on precisely the
fresh machine this repository exists to configure.

**ZSH-R-15** The rendered configuration SHALL name this repository's
configuration file as the orchestrator's global configuration. Activation
alone is insufficient: it resolves tools by walking upward from the working
directory (GEN-A-6), so it exposes them only beneath this repository, while
the fragments it replaced (ZSH-R-10, ZSH-R-11) were unconditional and
therefore machine-wide. The variable is read before configuration is parsed
and SHALL therefore be exported above the activation line and SHALL NOT be
set from `[env]`.

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
| ZSH-R-12 | The plugin loads in an interactive shell, and no symbolic link stands in for it |
| ZSH-R-13 | In the rendered file the five exports appear above the activation line; deleting any one of them, or moving it below the activation, fails the check |
| ZSH-R-13a | A shell started on a machine with no orchestrator prints nothing and exits zero; on a configured machine activation still takes effect |
| ZSH-R-14 | The rendered file contains no unsubstituted placeholder, and the framework path and the custom directory resolve to different roots |
| ZSH-R-15 | An interactive shell started outside this repository resolves every pinned tool by name and reports the pinned version, and resolves `cmake` to the pinned version rather than the system one |
| ZSH-A-8 | After setup the login shell is the absolute path to Zsh, and a second run reports it as already set |
