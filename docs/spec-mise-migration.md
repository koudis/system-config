# Spec: Replace shell orchestration with mise, remove submodules

Status: IMPLEMENTED except for the removal step - validated against upstream
sources 2026-08-15, then corrected against the pinned mise release (2026.8.6)
and the implemented `mise.toml` on 2026-08-16. See section 9 for what has and
has not run.
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

**Non-overlap is a constraint on where the repository is cloned, not only on
what setup writes.** A checkout placed inside the application directory
satisfies every requirement about file placement and still breaks GEN-R-3a:
deleting the application directory to rebuild the environment would delete the
repository, and with it anything else the user keeps there. `./setup` compares
`git rev-parse --show-toplevel` against `$APP_DIR` and warns, naming both
paths, once per run. It warns rather than refuses, and does not relocate the
default: an overlapping layout still works, it only makes one documented
recovery procedure destructive, and silently rewriting a user's install prefix
would be the larger surprise. Recorded in the README as well.

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
- Fetched *runtime content* (ohmyzsh, cmakelib) stays in the repository under
  `_vendor/`, gitignored. It is read at runtime, not installed. The one
  exception is zsh-autosuggestions, which is fetched to
  `zsh/custom/plugins/zsh-autosuggestions` - also inside the repository, also
  gitignored - because Oh My Zsh resolves custom plugins only under
  `$ZSH_CUSTOM/plugins/` (ZSH-A-7, ZSH-R-12). Fetching it to its real load path
  is preferred over fetching it to `_vendor/` and adding a symlink.
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
| `[bootstrap.packages]` (see 5.2) | all 6 `install_deps.sh` + `flatpak/setup.sh` |

### 5.1 Bootstrap wrapper

`MISE_DATA_DIR` is read at process start and **cannot** be set from
`mise.toml`'s `[env]`. A `./setup` wrapper at the repo root therefore:

1. Installs mise if absent.
2. Resolves the application directory setting (default `~/App`) and exports
   `MISE_DATA_DIR` beneath it.
3. Forwards its arguments to `mise run`, defaulting to `all` when given none
   (GEN-R-15).

Step 3 is what makes a single task runnable without bypassing the wrapper, and
the wrapper is the only place the process-start environment is prepared. It
matters for verification: `all` depends on `apps`, which installs roughly 15 GB
of desktop applications, so a harness run that could only run `all` would make
the rest of the work untestable.

The wrapper is not the only exporter of `MISE_DATA_DIR`. The rendered zshrc is
the second, and legitimately so - see 5.4.

### 5.2 System packages - use `[bootstrap.packages]`, with a fallback

mise has native declarative system-package support covering exactly this
repo's needs, including a **`flatpak` manager** alongside `dnf`:

- Managers are keyed `manager:package`, so packages are declared as `dnf:zsh`.
  With Fedora as the only target (GEN-A-2) the OS branching is not relocated
  but **deleted**, along with the second branch of every conditional.
- `mise bootstrap packages apply --dry-run --manager <manager>` prints commands
  without running them, supplying the dry-run this repo has never had.
- sudo elevation is explicit and logged. It never hangs waiting for a password.
- `[bootstrap.user]` with key `login_shell` adds the shell to `/etc/shells` and
  applies `chsh -s`. **This removes the manual `chsh` step** that
  `zsh/README.md` documents today. The value must be an absolute path
  (`/usr/bin/zsh`); mise rejects the bare name. Applying it needs
  `sudo env "PATH=$PATH" mise bootstrap user apply --yes`, because `chsh`
  authenticates the target user through PAM - which blocks on a password prompt
  for a non-root caller - and sudo's `secure_path` drops `$APP_DIR/bin`, where
  mise itself lives.
- Both managers' entries share one `[bootstrap.packages]` table, since TOML
  forbids a duplicate header; they are separated at apply time by `--manager`.

**The naming this section originally recorded was wrong.** An earlier draft
described the table as a `packages` table under a `system` table, applied by an
`install` subcommand beneath a `system` command group, on the basis of
upstream documentation that
described an in-progress rename. Probing the pinned binary shows the rename has
landed: mise 2026.8.6 has no `system` subcommand at all - `mise system --help`
errors out and `system` is absent from the top-level command list - while
`mise bootstrap packages --help` succeeds. The commands and tables above are
the ones actually in use in `mise.toml`. See GEN-A-8.

**Risk accepted with a fallback.** The subsystem remains gated behind mise's
experimental flag. If it proves disruptive, fall back to plain tasks shelling
out to `dnf` and `flatpak`, keeping the OS branching in exactly one task
instead of six files. The task DAG below is unchanged either way.

### 5.3 Task DAG

```
all
 +-- packages   dnf packages + build prerequisites + login_shell
 +-- flathub    ensure flatpak CLI + unfiltered Flathub remote  (depends: packages)
 +-- apps       17 applications, system scope                   (depends: flathub)
 +-- go         [tools] pin                                     (depends: packages)
 +-- cmake      [tools] pin, or source build                    (depends: packages)
 +-- fetch      clone/download + verify vendored sources
 +-- nvim-stamp write the Neovim freshness stamp, always runs
 +-- nvim       source build, RelWithDebInfo                    (depends: cmake, fetch, nvim-stamp)
 +-- render     sed templates -> generated files                (depends: fetch)
 +-- link       ln -sfn into $HOME                              (depends: render)
```

Three ordering constraints are load-bearing:

- `link` follows `render` because the symlink targets are generated files.
- `nvim` follows `nvim-stamp` because a freshness-gated task cannot write its
  own gate input - see 5.5.
- `apps` follows `flathub`, and therefore the Flatpak entries cannot be applied
  in the same step as the dnf entries. This is a direct consequence of
  APPS-A-5: mise will not create the remote, so it must exist first. Scoping
  each step with a manager filter keeps them separable.

**`render` refuses to overwrite a modified output.** The generated files
(`zsh/zshrc`, `vim/init.vim`) are gitignored, so a hand edit to one of them
exists in no template, no commit and no `git status` report. `render` produces
the new bytes first and compares: identical means the file is not touched at
all, which is what keeps the task a clean no-op on the second run; different
means the task stops and names the path. This is the same answer `fetch` and
`link` already give for vendored checkouts and `$HOME` targets, applied to the
one location where the destroyed content would have been genuinely
unrecoverable.

### 5.4 PATH contract

The rendered zshrc exposes installed tools via the orchestrator's shell
activation rather than by appending literal path fragments; the removed
`___USER_BIN_DIR___` and `___GO_BIN_DIR___` placeholders are what that
replaces. During the *first* run
that directory is not yet on `PATH`, so the `nvim` task must invoke cmake by
explicit path rather than relying on a bare `cmake`. The current
`vim/setup.sh` relies on `PATH` and only works because a system cmake happens
to be present.

**The rendered zshrc exports `APP_DIR`, `MISE_DATA_DIR` and `PATH` before it
activates mise, in that order** (ZSH-R-13). mise reads `MISE_DATA_DIR` at
process start, so activating first means an ordinary interactive shell falls
back to mise's default data directory - and every tool installed from that
shell then lands outside the application directory, breaking the section 4
invariant. This makes the rendered profile a second legitimate exporter of
`MISE_DATA_DIR` beside `./setup`, and it corrects the earlier wording that
`./setup` is the only place allowed to export it. The two exporters are not
duplication: they cover two different process lifetimes, and both derive the
value from the application-directory setting rather than from a literal path.

Activation itself is guarded on mise existing (ZSH-R-13a). A guard on whether a
command exists is not an operating-system conditional and is not what GEN-R-8
prohibits: GEN-R-8 targets branching on the platform, which is dead code in a
Fedora-only repository, whereas this branches on whether setup has run yet -
the normal state of the fresh notebook this repository exists to configure. The
same idiom is used at `setup:14` and `test/run.sh:29`. See GEN-R-8b.

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
   task takes a single file (`.build/nvim.version`, holding the pinned version
   and the install prefix) as its only `source`, and a single binary as its
   only `output`. This expresses the intent exactly - rebuild when the pin
   changes - and sidesteps all three failure modes plus the cost of scanning a
   large source tree.
3. **Write the stamp from a separate, ungated task that runs first**
   (`nvim-stamp`, GEN-R-18, NVIM-R-10). A stamp written inside the gated build
   cannot invalidate the gate that guards it: the write happens only after mise
   has already decided whether to run the task, so a version bump would never
   rebuild. Because `source_freshness_hash_contents` compares content and the
   stamp is a pure function of the pin and the prefix, an unchanged pin
   reproduces the same bytes and the build is still correctly skipped.

Note mise automatically includes the config file itself in `sources`, so
editing `mise.toml` correctly invalidates dependent tasks.

Two upstream bugs in this area are already fixed and require no workaround: a
failed task no longer advances the source-hash baseline (PR #11296), and a
failed forced rerun no longer leaves an auto-output marker behind (PR #10953).

## 6. Source pins

Submodules are superseded, and their sources split by role. Deleting the
gitlinks themselves is section 9 step 4, which has not run.

### 6.0 The orchestrator itself

mise is a pinned source like any other, and for a while it was the only one
that was not: `./setup` piped `https://mise.run` with no version, while the
whole design depends on `[bootstrap.packages]` and `mise bootstrap packages
apply` - an experimental interface that has already been renamed once under
this repository (RR1, GEN-A-8). An unpinned orchestrator means an upstream
release can change that interface between two runs of a script whose purpose
is reproducibility.

The pin is `min_version = "2026.8.6"` at the top of `mise.toml`, so acceptance
criterion 5 holds for the orchestrator too. It has two readers, deliberately:

- mise itself enforces it at run time, refusing to load the config with an
  older binary.
- `./setup` extracts the same line with `sed` and passes it to the installer as
  `MISE_VERSION`. The wrapper runs *before* mise exists, so it cannot ask mise
  to parse its own config; reading the file directly is the only way to keep
  the pin in `mise.toml` instead of duplicating it as a shell constant, which
  GEN-R-7 forbids.

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
zsh-autosuggestions is fetched to `zsh/custom/plugins/zsh-autosuggestions`
rather than to `_vendor/`, for the reason given in section 4.

**Fetching never destroys a path it did not create** (GEN-R-17, GEN-R-17a).
The fetch step refuses, without deleting, if the target path is a registered
submodule of this repository or a git work tree with uncommitted changes, and
it fails naming the path. The refusal covers `checkout --force` as well as
`rm -rf`, because a forced checkout discards uncommitted work just as
effectively. The submodules have since been removed (section 9), so the
refusal now guards a re-introduced gitlink or a dirty plain clone rather than
the checkouts that were live while the migration ran. A clean clone already at the pinned
ref is reused in place and not re-fetched, which is also what keeps the step a
no-op on a second run.

The same principle governs deployment: `link` refuses to replace a `$HOME`
target that exists and is not already a symlink into this repository, and
replaces an existing correct symlink silently so re-runs stay idempotent
(GEN-R-17b, KITTY-R-4). The harness runs in a throwaway container, so the loss
this prevents is one the tests could never show.

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
extracted once from the pinned Oh My Zsh checkout, with the single change the
patch made, and committed as `zsh/custom/themes/muse.zsh-theme`; `ZSH_CUSTOM`
already points at `zsh/custom`, and the directory exists for this purpose. The
committed file is the only remaining copy of that change, and the patch file is
deleted (ZSH-R-4).

`ZSH_CUSTOM` gets its own template placeholder, `___ZSH_CUSTOM_DIR___`
(ZSH-R-14). It cannot share the framework-path placeholder: the framework is
fetched runtime content under `_vendor/` while the custom directory is committed
repository content under `zsh/`, and one placeholder cannot yield two unrelated
roots.

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

Template placeholders. Two are ported, one is **added**, three are **deleted**:

| Placeholder | Disposition |
|---|---|
| `___CMAKELIB_DIR___` | deleted - cmakelib's environment moves to the tool layer, see below |
| `___OHMYZSH_PROJECT_DIR___` | ported |
| `___VIM_BASE_DIR___` | ported |
| `___ZSH_CUSTOM_DIR___` | added - the custom directory is a second, unrelated root (ZSH-R-14) |
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
| `mise.toml` - the single pin and task file | written |
| `./setup` - bootstrap wrapper | written |
| Converted templates, extracted theme, `.gitignore` | written |
| `test/` - containerised verification harness | written |

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

**Status.** All six steps are done, in that order, task by task through the
containerised harness. Steps 4 and 5 removed all 9 gitlinks - including the
orphaned `cmakelib-component-cmconf` - `.gitmodules`, the submodule object
stores under `.git/modules`, and all 14 shell scripts. `git ls-files -s`
reports no mode-160000 entry and `git submodule status` reports nothing. The
two consequences that held while the removal was pending are resolved: the
broken `zsh/setup.sh`, which still referenced the `zsh/template/config_template`
deleted in step 6, is gone with the rest. The fetch step's refusal to touch a
registered submodule (6.2) now guards only a re-introduced one, so it is a
regression guard rather than a live safeguard, and it is retained as such.

## 10. Acceptance criteria

1. `git clone <https-url> && cd && ./setup` succeeds on a fresh Fedora box with
   no SSH key configured.
2. A second `./setup` immediately afterwards is a no-op for every task and
   exits non-zero nowhere.
3. `git submodule status` reports nothing.
4. No file outside the repository and the application directory except the
   three symlinks and their parent dirs.
5. Every version pin appears in `mise.toml`, including mise's own
   (`min_version`, see 6.0).
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

- **RR1 (medium): the bootstrap subsystem is experimental.** The rename part of
  this risk has materialised and is resolved: the interface is
  `[bootstrap.packages]` and `mise bootstrap packages apply`, not the names
  this document originally recorded (5.2, GEN-A-8). What remains is that an
  experimental subsystem may change again. Mitigation: the 5.2 fallback to
  plain dnf/flatpak tasks; the DAG does not change.
- **RR2 (low): mise freshness bugs.** Two relevant upstream bugs are still
  open (#7656 multiple outputs, #4209 deleted sources). Mitigated by the
  single-source/single-output version-stamp design in 5.5, which avoids both.
- **RR3 (low): `MISE_DATA_DIR` under the application directory is a
  non-default layout.** Must be exported by the wrapper, never from `[env]`.
- **RR4 (low): tag/SHA pins are not checksummed** for the git-cloned content,
  unlike the tarballs. Accepted; SHAs are immutable in practice.
- **RR5 (medium): the flatpak apply path is never exercised in a container.**
  The harness proves the Flathub remote exists, is unfiltered, and resolves all
  17 application IDs; it never installs them. A resolvable ID can still fail to
  install for reasons no check covers - disk space, architecture, runtime
  conflicts - and the first real signal comes from the user's own machine. A
  real `flatpak install --system` needs a working system bus the sandboxed
  container does not have, so nothing cheap closes this. Bounded by the fact
  that the same apply mechanism is proven with `--manager dnf`. See APPS-A-9.
- **RR6 (low): the login-shell change needs an absolute path and elevation with
  `PATH` forwarded.** `login_shell` must be `/usr/bin/zsh`; mise rejects the
  bare name. Applying it requires
  `sudo env "PATH=$PATH" mise bootstrap user apply --yes`, because `chsh`
  authenticates through PAM and sudo's `secure_path` drops `$APP_DIR/bin`. The
  apply is unconditional, so it asks for elevation on every run even when the
  shell is already set. See ZSH-A-8 and ZSH-A-9.

Resolved during validation, in order of discovery: ohmyzsh tarball breakage
(now specified as a git clone, 6.2); Neovim tarball version stamping (safe at
v0.11.6, 6.1); Go and ghcup as unmanaged dependencies (7.1); the `ag` and
`python-neovim` package-name errors and the missing build prerequisites (7);
and finally APPS-A-5 - mise does not configure Flatpak remotes, which added the
`flathub` step and its ordering constraint (5.3, 7.2).

Resolved during implementation: the mise interface naming (5.2, RR1), which was
the one factual claim in this document that the pinned binary contradicted.

**No open assumptions and no open decisions remain.** The six risks above are
accepted with mitigations, not unknowns.
