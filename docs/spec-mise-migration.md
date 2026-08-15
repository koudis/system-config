# Spec: Replace shell orchestration with mise, remove submodules

Status: DRAFT - validated against upstream sources 2026-08-15
Repo: system config for a fresh Fedora notebook (Fedora only - see GEN-A-2)

## 1. Problem

The repo bootstraps a workstation with 14 shell scripts (`setup.sh`, `lib.sh`,
and a `setup.sh` + `install_deps.sh` pair per tool). Concrete defects:

- **Not re-runnable.** `kitty/setup.sh:8` calls `ln -s` with no preceding
  `rm -f` and never creates `~/.config/kitty`. Second run fails; first run on a
  fresh box fails if kitty has not yet created its config dir.
- **No state tracking.** Every run re-clones, re-patches, re-compiles and
  re-links unconditionally. No dry-run, no diff, no drift visibility.
- **Dead error handling.** `lib.sh:check_if_command_is_installed` tests `$?`
  after `which`, but `set -e` aborts the function before the test is reached.
  Verified: the diagnostic message is unreachable.
- **Broken submodules.** 9 gitlinks exist but only 8 are declared in
  `.gitmodules`; `cmakelib/cmakelib-component-cmconf` is orphaned. Today
  `git submodule status` errors out and `git clone --recurse-submodules`
  silently under-populates cmakelib.
- **SSH bootstrap failure.** 4 of 8 declared submodules use
  `git@github.com:`. A fresh notebook with no key uploaded cannot clone them,
  which defeats the repo's only purpose.
- **Version pins scattered across three mechanisms.** Gitlink SHAs (ohmyzsh,
  cmakelib), shell constants (`CMAKE_VERSION`, `NVIM_VERSION`), and nothing at
  all for anything else.
- **Hidden cross-tool coupling.** `cmakelib/setup.sh` is a no-op; the real
  cmakelib configuration is emitted from `zsh/template/config_template`.
- **Hand-written OS branching.** Every `install_deps.sh` repeats
  `if debian -> apt / if fedora -> dnf`, for a second platform that is now out
  of scope entirely (GEN-A-2).

## 2. Goals

1. One orchestrator, one config file, replacing all 14 scripts.
2. Idempotent: re-running is the normal case and skips unchanged work.
3. Declared ordering instead of ordering implied by line position.
4. All version pins in one visible, diffable file.
5. Zero git submodules.
6. Fresh-laptop bootstrap works with no pre-existing SSH key.
7. Zero operating-system conditionals (GEN-R-8), following from Fedora-only
   scope.

## 3. Non-goals

- Migrating to Nix, Ansible, chezmoi, or Fedora image mode. Evaluated and
  rejected in favour of keeping the current containment model.
- Managing Neovim plugins. `lazy.nvim` already owns `vim/plugin/*` against its
  own lockfile; it stays as-is.
- Multi-machine or multi-user support. Single user, single laptop at a time.
- Any platform other than Fedora. Debian was previously a declared-but-untested
  secondary; it is now out of scope entirely (GEN-A-2), which removes the second
  branch of every operating-system conditional rather than relocating it.

## 4. Hard invariant

**The repository owns configuration, sources and pins. A configurable
application directory owns installed artifacts. `$HOME` receives symlinks
only.**

This supersedes an earlier formulation ("everything inside the repository")
that placed build outputs in the repository. Installed binaries and SDKs go to
a single configurable application directory, default `~/App`. The two locations
do not overlap: no templates or pins in the application directory, no installed
artifacts in the repository. See GEN-D-13, GEN-R-1a, GEN-R-1b, GEN-R-1c in
`requirements/general.md`.

This also consolidates a split that exists today, where `setup.sh` installs
binaries to `$HOME/Bin` while `lib.sh` points the Go SDK at
`$HOME/App/go/go1.23.3` - two prefixes, one of them hardcoded.

This is why chezmoi was rejected: its source of truth defaults to
`~/.local/share/chezmoi`, it writes copies rather than symlinks, its externals
fetch into `$HOME`, and its `run_onchange_` state is a boltdb under
`~/.config/chezmoi/`. Four violations.

Consequences:

- The application directory is a single setting, default `~/App`, referenced
  everywhere by that setting and never by literal path.
- Build prefix moves from `$HOME/Bin` to the application directory.
- `MISE_DATA_DIR` is set under the application directory. Upstream notes tool
  installs are machine-local and not meant to be shared, so they are never
  committed - which holds by construction, since the directory is outside the
  repository.
- The Go SDK moves from its hardcoded path into the same directory, installed
  rather than assumed.
- Fetched *runtime content* (ohmyzsh, autosuggestions, cmakelib) stays in the
  repository under `vendor/`, gitignored. It is read at runtime, not installed.
- Fetched *build inputs* (Neovim, CMake sources) land in `<repo>/.build`,
  gitignored, and are scratch.
- Deleting the application directory and re-running setup restores a working
  environment (GEN-R-3a).
- The only things outside the repository and the application directory are the
  three symlinks and their parent dirs.

## 5. Architecture

`mise` is the sole orchestrator. A repo-root `mise.toml` is mise's native
config-resolution case (it walks up from cwd), so no global config is involved.

| Feature | Replaces |
|---|---|
| `[tasks]` with `depends` | `. ${project_setup}` sourcing + `unset setup` hack |
| `sources` / `outputs` | nothing - new; provides idempotence |
| `[tools]` | `CMAKE_VERSION` constant + `cmake/CMake` submodule, plus Go, previously unmanaged |
| `[system.packages]` (see 5.2) | all 6 `install_deps.sh` + `flatpak/setup.sh` |

### 5.1 Bootstrap wrapper

`MISE_DATA_DIR` is read at process start and **cannot** be set from
`mise.toml`'s `[env]`. A `./setup` wrapper at the repo root therefore:

1. Installs mise if absent.
2. Resolves the application directory setting (default `~/App`) and exports
   `MISE_DATA_DIR` beneath it.
3. Runs `mise run all`.

### 5.2 System packages - use `[system.packages]`, with a fallback

mise has native declarative system-package support covering exactly this
repo's needs, including a **`flatpak` manager** alongside `dnf`:

- Managers are keyed `manager:package`, so packages are declared as `dnf:zsh`.
  With Fedora as the only target (GEN-A-2) the OS branching is not relocated
  but **deleted**, along with the second branch of every conditional.
- `mise system install --dry-run` prints commands without running them,
  supplying the dry-run this repo has never had.
- sudo elevation is explicit and logged; `system_packages.sudo = false`
  forbids it and prints the command instead. It never hangs waiting for a
  password.
- `[system].login_shell` adds the shell to `/etc/shells` and applies `chsh -s`.
  **This removes the manual `chsh` step** that `zsh/README.md` documents today.
- `mise bootstrap --yes` is a single fresh-machine entry point and runs a task
  named `bootstrap` afterwards if defined.

**Risk accepted with a fallback.** This subsystem is gated behind mise's
experimental flag, and upstream is mid-rename: the same functionality is
documented as both `mise system install` / `[system.packages]` and
`mise bootstrap packages apply` / `[bootstrap.packages]`. If that churn proves
disruptive, fall back to plain tasks shelling out to `dnf` and `flatpak`,
keeping the OS branching in exactly one task instead of six files. The task
DAG below is unchanged either way.

### 5.3 Task DAG

```
all
 +-- packages   dnf packages + build prerequisites + login_shell
 +-- flathub    ensure flatpak CLI + unfiltered Flathub remote  (depends: packages)
 +-- apps       17 applications, system scope                   (depends: flathub)
 +-- go         [tools] pin                                     (depends: packages)
 +-- cmake      [tools] pin, or source build                    (depends: packages)
 +-- fetch      clone/download + verify vendored sources
 +-- nvim       source build, RelWithDebInfo                    (depends: cmake, fetch)
 +-- render     sed templates -> generated files                (depends: fetch)
 +-- link       ln -sfn into $HOME                              (depends: render)
```

Two ordering constraints are load-bearing:

- `link` follows `render` because the symlink targets are generated files.
- `apps` follows `flathub`, and therefore the Flatpak entries cannot be applied
  in the same step as the dnf entries. This is a direct consequence of
  APPS-A-5: mise will not create the remote, so it must exist first. Scoping
  each step with a manager filter keeps them separable.

### 5.4 PATH contract

The rendered zshrc exposes installed tools via the orchestrator's shell
activation rather than by appending literal path fragments; the removed
`___USER_BIN_DIR___` and `___GO_BIN_DIR___` placeholders are what that
replaces. During the *first* run
that directory is not yet on `PATH`, so the `nvim` task must invoke cmake by
explicit path rather than relying on a bare `cmake`. The current
`vim/setup.sh` relies on `PATH` and only works because a system cmake happens
to be present.

### 5.5 Freshness strategy for build tasks

mise's default freshness check is mtime-based and has known failure modes that
this repo would hit directly:

- Sources extracted from a tarball can carry UNIX-epoch mtimes; mise treats
  those as permanently stale, so the build would re-run every time.
- With multiple `outputs`, a task is skipped if *any one* output exists even
  when others are missing (upstream discussion #7656, open).
- Deleted source files are not detected (upstream discussion #4209, open).

Therefore:

1. Set `task.source_freshness_hash_contents = true` to hash contents instead
   of trusting mtime.
2. **Key build freshness on a version stamp, not the source tree.** Each build
   task takes a single-line file (`.build/nvim.version` containing `v0.11.6`)
   as its only `source`, and a single binary as its only `output`. This
   expresses the intent exactly - rebuild when the pin changes - and sidesteps
   all three failure modes plus the cost of scanning a large source tree.

Note mise automatically includes the config file itself in `sources`, so
editing `mise.toml` correctly invalidates dependent tasks.

Two upstream bugs in this area are already fixed and require no workaround: a
failed task no longer advances the source-hash baseline (PR #11296), and a
failed forced rerun no longer leaves an auto-output marker behind (PR #10953).

## 6. Source pins

Submodules are removed and split by role.

### 6.1 Build inputs - fetch release tarball, verify sha256

The gitlink is already dead weight for these two: the version is decided by a
shell constant (`git checkout ${CMAKE_VERSION}`), and `setup.sh` wraps the
build in `git clean -xfd` on both sides, so the tree is already scratch. A
checksummed tarball is a stronger pin than a tag and avoids cloning large
histories.

| Source | Version | Notes |
|---|---|---|
| CMake | v3.30.1 | may be dropped entirely in favour of `[tools] cmake` |
| Neovim | v0.11.6 | source build required for `CMAKE_BUILD_TYPE=RelWithDebInfo` |

**Neovim tarball builds are safe at this version.** `cmake/GenerateVersion.cmake`
runs `git describe` and falls back to the CMake-declared `NVIM_VERSION` when
git fails. For a *release* tag that fallback is already the correct string, so
`nvim --version` reports `v0.11.6`. The historical corruption cases were
prerelease (`v0.8.0-dev`) builds. Note the closest known failure mode is
exactly this repo's layout - a release tarball extracted *inside another git
repository* - which was fixed upstream in PR #20993 and backported to 0.8, so
v0.11.6 is unaffected.

### 6.2 Runtime content - pinned https clone

These persist on disk and are referenced live by config (`ZSH=`,
`CMLIB_DIR=`); they are never built. The gitlink SHA is currently the only
pin, so an explicit ref must be recorded or these silently start tracking
`master`. All URLs move to `https://`, removing the SSH bootstrap failure.

| Source | Current pin | Recorded as |
|---|---|---|
| ohmyzsh | `b54a7197` (no tag) | SHA |
| zsh-autosuggestions | `v0.7.0-12-gc3d4e57` | SHA |
| cmakelib | `v1.3.4-1-g3bd355a` | SHA |
| cmakelib-component-cmconf | `v1.2.1` | tag |
| cmakelib-component-cmdef | `v1.0.3` | tag |
| cmakelib-component-cmutil | `v1.1.0-3-g66ea4a9` | SHA |
| cmakelib-component-storage | `v1.0.0` | tag |

`cmconf` is the currently-orphaned gitlink; it is declared properly here.

**ohmyzsh must be a git clone, not a tarball.** Verified against ohmyzsh's own
`tools/check_for_upgrade.sh`: it aborts with "Can't update: not a git
repository" unless `$ZSH` is a git work tree, and `is_update_available()` reads
`git config --local oh-my-zsh.remote` and `oh-my-zsh.branch`. The rendered
zshrc sets `zstyle ':omz:update' mode reminder`, so a tarball install would
break updates permanently. Upstream closed the tarball-install request (#11778)
on exactly this ground.

Two further ohmyzsh constraints taken from its `tools/install.sh`:

- Clone under `umask g-w,o-w`. Group- or world-writable `$ZSH` makes
  `compinit` fail with "command not found: compdef".
- The installer sets `git config oh-my-zsh.remote origin` and
  `oh-my-zsh.branch <branch>`; a plain clone provides the former, and the
  latter defaults to `master` when unset.

### 6.3 ohmyzsh theme

`zsh/muse_theme.patch` is dropped. Patching a freshly fetched tree is not
idempotent and breaks whenever upstream moves. The patched theme is instead
committed as `zsh/custom/themes/muse.zsh-theme`; `ZSH_CUSTOM` already points at
`zsh/custom`, and the directory exists for this purpose.

## 7. Managed inventory

Runtime packages: `direnv`, `fzf`, `the_silver_searcher`, `zsh`, `kitty`,
`python3-neovim`.

Two corrections against the current lists (GEN-R-14): the repo declares `ag`,
which is a binary name and not a Fedora package, and `python-neovim`, which is
the source package rather than the installable `python3-neovim` subpackage.

Neovim build prerequisites, verbatim from upstream: `ninja-build`, `cmake`,
`gcc`, `make`, `gettext`, `curl`, `glibc-gconv-extra`, `git`. Nothing in the
repo installs any of these today. `glibc-gconv-extra` is the trap - split out
of glibc in Fedora 35+, and without it the build fails on charset errors.

Desktop applications (17): KiCad, FreeCAD, Anki, Obsidian, PrusaSlicer, drawio,
Bottles, TeXstudio, OnlyOffice, JOSM, GitKraken, Krita, Flatseal, GNOME
Extensions, Extension Manager, Arduino IDE2, Tellico. All tier 1 (Flatpak),
installed **system-wide** - see 7.2.

Template placeholders. Three are ported, two are **deleted**:

| Placeholder | Disposition |
|---|---|
| `___CMAKELIB_DIR___` | deleted - cmakelib's environment moves to the tool layer, see below |
| `___OHMYZSH_PROJECT_DIR___` | ported |
| `___VIM_BASE_DIR___` | ported |
| `___USER_BIN_DIR___` | deleted - superseded by mise shell activation (ZSH-R-10) |
| `___GO_BIN_DIR___` | deleted - superseded by mise shell activation (GO-R-2) |

### 7.1 Unmanaged external dependencies (found during validation)

A coverage check of the spec against every file and function the AST extracted
from the repo surfaced two dependencies the repo references but never installs.
Both violate the section 4 invariant and both are latent breakage on a fresh
notebook.

**Go SDK.** `lib.sh:76` hardcodes `$HOME/App/go/go1.23.3/`. Nothing in the repo
installs Go, yet `get_go_sdk_dir` feeds `___GO_BIN_DIR___` straight into the
rendered zshrc's `PATH`. On a fresh machine that PATH entry points at a
directory that does not exist. `check_install_dir` does not catch it - it only
tests for an empty string.

Resolution: `[tools] go = "1.23.3"` in `mise.toml`. Version management is
mise's core competency, the pin joins every other pin in one file, and the
hardcoded `$HOME` path disappears. `___GO_BIN_DIR___` is then dropped from the
template entirely, since `mise activate` puts Go on `PATH`.

**ghcup.** `zsh/template/zshrc_template:163` sources `/home/h/.ghcup/env` - an
absolute path with the username baked in, not even `$HOME`-relative. Nothing in
the repo installs ghcup, and the line breaks on any other username.

Resolution: **delete the line.** Verified on the current machine that
`~/.ghcup` does not exist, that none of `ghc`, `ghci`, `cabal`, `stack` or
`ghcup` are on `PATH`, and that no Haskell sources exist in the repo (the sole
`.hs` file is a treesitter test fixture under `vim/plugin/`). The line is dead;
its `[ -f ... ]` guard is why it fails silently instead of erroring, which is
how it survived unnoticed.

If Haskell is ever needed again it comes back as a mise tool alongside Go, not
as a hardcoded path in a shell template.

Symlinks deployed: `~/.zshrc`, `~/.config/nvim/init.vim`,
`~/.config/kitty/kitty.conf`. All created with `ln -sfn`, parents created
first.

`~/.zshrc_config` is retired. Its source, `zsh/template/config_template`,
contains only the two cmakelib exports and a no-op `PATH` assignment. Those
exports are declared in the pin file's environment block instead, where the
cmakelib tool owns them, and reach the shell through mise activation. That
removes the repository's clearest hidden coupling - cmakelib's own setup step
is a no-op today while its environment is emitted from the shell's template
(CMLIB-A-3) - and satisfies GEN-R-9, ZSH-R-9 and CMLIB-R-3 together. One fewer
rendered file, one fewer symlink, one fewer placeholder.

### 7.2 Desktop applications: tiers, scope and the remote

**Acquisition order** is Flatpak, then `dnf`, then manual - applied *when an
application is added*, with the resulting tier recorded, never as a runtime
fallback chain (APPS-R-2). A chain would make the same repo produce different
machines, and it would not work anyway: when the Flatpak CLI is absent mise
*skips* those entries rather than failing, so a fall-through rule installs
nothing instead of advancing. Tier 3 is per-application, not a blanket promise -
GitKraken is proprietary and has no buildable source (APPS-R-3).

**Scope is system-wide** (APPS-R-6), matching current behaviour, so no silent
migration of 17 applications between scopes.

**The remote is this repo's responsibility.** mise does not install Flatpak or
configure remotes implicitly, so an explicit preceding step must ensure the CLI
is present and an unfiltered Flathub remote exists (APPS-R-7). Flathub is not
guaranteed on Fedora - it is opt-in via Third-Party Repositories, and enabling
it that way may yield a *filtered* remote exposing only a Fedora-approved
subset. The current implementation adds no remote at all, so on a fresh box all
17 fail.

## 8. Deliverables

Documentation is part of the work, not a by-product of it. The full set:

| Deliverable | Status |
|---|---|
| `docs/spec-mise-migration.md` (this file) | written |
| `docs/requirements/README.md` - index and conventions | written |
| `docs/requirements/general.md` - definitions, global assumptions, global requirements | written |
| `docs/requirements/tool-zsh.md` | written |
| `docs/requirements/tool-neovim.md` | written |
| `docs/requirements/tool-cmake.md` | written |
| `docs/requirements/tool-cmakelib.md` | written |
| `docs/requirements/tool-go.md` | written |
| `docs/requirements/tool-kitty.md` | written |
| `docs/requirements/tool-desktop-apps.md` | written |
| `docs/adding-a-new-tool.md` - the explicit procedure | written |
| `mise.toml` - the single pin and task file | pending |
| `./setup` - bootstrap wrapper | pending |
| Converted templates, extracted theme, `.gitignore` | pending |

The requirements documents are normative: `mise.toml` implements them, and
GEN-R-13 requires a document per managed tool. Adding a tool without its
document is incomplete work, and the procedure for doing it correctly is
`docs/adding-a-new-tool.md`.

## 9. Migration

Separate, revertable commits:

1. Add the documentation set above. No behaviour change.
2. Add `mise.toml`, `./setup`, `.gitignore` entries. Nothing removed yet.
3. Verify a full run in a throwaway VM or container, from a clean state.
4. `git rm` the 9 gitlinks, delete `.gitmodules`, `rm -rf .git/modules/*`.
5. Delete the 14 shell scripts and `lib.sh`.
6. Commit `zsh/custom/themes/muse.zsh-theme`, delete `muse_theme.patch`.

## 10. Acceptance criteria

1. `git clone <https-url> && cd && ./setup` succeeds on a fresh Fedora box with
   no SSH key configured.
2. A second `./setup` immediately afterwards is a no-op for every task and
   exits non-zero nowhere.
3. `git submodule status` reports nothing.
4. No file outside the repository and the application directory except the
   three symlinks and their parent dirs.
5. Every version pin appears in `mise.toml`.
6. `nvim --version` reports `v0.11.6`, build type RelWithDebInfo.
7. `omz update` works (proves ohmyzsh kept a usable `.git`).
8. `zsh` is the login shell without a manual `chsh`.
9. Every entry in the rendered `PATH` exists. Specifically, no reference to
   `$HOME/App/go/...` survives, and `go version` works.
10. No absolute path containing a hardcoded username appears anywhere in the
    repo (`grep -rn '/home/[a-z]' --include='*_template'` returns nothing).
11. All 17 applications install on a box with Third-Party Repositories disabled
    and no Flathub remote configured, and all report system scope.
12. Every declared package name resolves in Fedora's repositories - in
    particular `the_silver_searcher` and `python3-neovim`, not `ag` and
    `python-neovim`.
13. The Neovim build succeeds on a Fedora box with no development tooling
    pre-installed, proving the prerequisite list is complete.
14. No operating-system conditional exists anywhere in the repository
    (GEN-R-8).
15. Every managed tool has a requirements document (GEN-R-13); the identifier
    integrity check reports zero dangling citations.

## 11. Residual risks

- **RR1 (medium): `[system]` is experimental and mid-rename.** Mitigation: the
  5.2 fallback to plain dnf/flatpak tasks; the DAG does not change.
- **RR2 (low): mise freshness bugs.** Two relevant upstream bugs are still
  open (#7656 multiple outputs, #4209 deleted sources). Mitigated by the
  single-source/single-output version-stamp design in 5.5, which avoids both.
- **RR3 (low): `MISE_DATA_DIR` under the application directory is a
  non-default layout.** Must be exported by the wrapper, never from `[env]`.
- **RR4 (low): tag/SHA pins are not checksummed** for the git-cloned content,
  unlike the tarballs. Accepted; SHAs are immutable in practice.

Resolved during validation, in order of discovery: ohmyzsh tarball breakage
(now specified as a git clone, 6.2); Neovim tarball version stamping (safe at
v0.11.6, 6.1); Go and ghcup as unmanaged dependencies (7.1); the `ag` and
`python-neovim` package-name errors and the missing build prerequisites (7);
and finally APPS-A-5 - mise does not configure Flatpak remotes, which added the
`flathub` step and its ordering constraint (5.3, 7.2).

**No open assumptions and no open decisions remain.** The four risks above are
accepted with mitigations, not unknowns.
