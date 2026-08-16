# Splitting setup into a privileged and an unprivileged phase

Date: 2026-08-16

## 1. Purpose

`./setup` currently elevates in three places, and a single run mixes work that
needs root with work that does not:

| Location | Command | Why it elevates |
|---|---|---|
| `mise.toml:88` | `mise bootstrap packages apply --manager dnf` | dnf writes to `/usr`; mise elevates internally |
| `mise.toml:89` | `sudo env "PATH=$PATH" mise bootstrap user apply --yes` | `chsh` authenticates through PAM; sudo skips the prompt |
| `mise.toml:99` | `sudo flatpak remote-add --if-not-exists flathub ...` | the remote is system-scope |

The consequence is that no part of setup can be run without elevation, even the
parts that only clone repositories, render templates and create symlinks in
`$HOME`.

This design splits setup in two. One phase is allowed to elevate and does
nothing else. The other phase never elevates, and that property is enforced by
the verification harness rather than asserted in a comment.

`GEN-A-5` ("sudo is available and interactive") is not deleted. It is narrowed
to the privileged phase.

## 2. Decisions

Recorded here because each was a fork with a real cost, not a default.

| Decision | Chosen | Rejected alternative |
|---|---|---|
| Shape of the split | Two aggregate mise tasks behind the one `./setup` wrapper | Two wrapper scripts; a `--with-system` flag |
| Missing prerequisites in the unprivileged phase | Block, naming exactly what is absent | Fail naturally inside the Neovim build; warn and continue |
| Proof that the unprivileged phase is sudo-free | A second container image with no `sudo` installed | A `sudo` shim on `PATH`; a static grep of task bodies |
| Flatpak install scope | User scope, so the applications become unprivileged | System scope, keeping the applications in the privileged phase |
| Flatpak mechanism | The `flatpak` command driven directly from the task body | mise's `flatpak-user` manager and the declarative table |
| Preflight's command list | Only what the unprivileged tasks execute | The whole resulting environment, including `zsh` and `kitty` |
| Preflight failure path | Tested, by an expect-fail run on the bare image | Left untested |

## 3. Task topology

### 3.1 Privileged phase

```
[tasks.packages]      mise bootstrap packages apply --yes --manager dnf
[tasks.login-shell]   sudo env "PATH=$PATH" mise bootstrap user apply --yes
[tasks.system]        depends = ["packages", "login-shell"]
```

`[tasks.packages]` today carries both of these commands under one comment block
covering two unrelated subjects, which is why the `chsh` rationale reads as if
it explains `--manager dnf`. They separate into two tasks with one subject each.

After the split, `mise.toml` contains exactly one `sudo` invocation, at
`[tasks.login-shell]`, plus mise's own internal elevation for dnf. Both are
reachable only from `[tasks.system]`. Comments elsewhere still name `sudo` when
explaining why a step does or does not elevate.

### 3.2 Unprivileged phase

```
[tasks.preflight]
[tasks.flathub]       depends = ["preflight"]
[tasks.apps]          depends = ["flathub"]
[tasks.tools]         depends = ["preflight"]
[tasks.fetch]
[tasks.nvim-stamp]
[tasks.nvim]          depends = ["tools", "preflight", "nvim-stamp"]
[tasks.render]        depends = ["fetch"]
[tasks.link]          depends = ["render"]
[tasks.all]           depends = ["preflight", "apps", "tools", "fetch", "nvim", "render", "link"]
```

Every existing `depends = ["packages"]` becomes `depends = ["preflight"]`. The
bodies of `fetch`, `nvim-stamp`, `nvim`, `render` and `link` are not modified at
all; only their dependency lists change.

`apps` remains inside `all`, as today. `test/run.sh` therefore still must never
default to `all` - that is the ~15 GB path, which after this change lands in
`$HOME` rather than `/var`.

### 3.3 Invocation

```
sudo -v
./setup system     # once per machine; the only command that elevates
./setup            # no elevation, ever
```

`./setup` is unchanged: it already ends in `exec mise run "${@:-all}"`
(`setup:53`), so the split is expressed entirely in task names. No wrapper
duplication, one `APP_DIR`/`MISE_DATA_DIR` export, one mise bootstrap path.

### 3.4 Preview

`GEN-R-10` requires a mode that reports what would change without changing it.
The single `[tasks.preview]` splits along the same seam:

```
[tasks.preview]         mise run --dry-run all
                        <the application diff described below>
[tasks.preview-system]  mise run --dry-run system
                        mise bootstrap packages apply --dry-run --manager dnf
```

This split is load-bearing, not cosmetic: `checks-bootstrap.sh` asserts that
`mise run preview` succeeds, and that check now runs inside the sudo-less
image, so `preview` must not reach for dnf.

Driving `flatpak` directly (section 5) costs the free
`mise bootstrap packages apply --dry-run` that the declarative table would have
provided, so the application half of the preview is hand-rolled: list what is
installed in user scope and print the configured identifiers that are absent.

```
installed=$(flatpak list --user --columns=application)
for app in $APPS; do
    grep -qx "$app" <<<"$installed" || echo "would install: $app"
done
```

This is the whole of `GEN-R-10` for the application step: it reports what would
change and changes nothing.

## 4. Preflight

```
[tasks.preflight]
run = """
set -euo pipefail
missing=()
for c in git curl gcc make ninja msgfmt flatpak; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if (( ${#missing[@]} )); then
    echo "preflight: missing required commands: ${missing[*]}" >&2
    echo "preflight: these come from the privileged half" >&2
    echo "preflight: run './setup system' first, or install them yourself" >&2
    exit 1
fi
"""
```

Silent on success. The failure message is required for correctness, not
decoration: it is the only thing that tells the user the privileged phase was
never run, and it follows the refuse-and-name-the-path style the `fetch`,
`render` and `link` guards already use.

**The list gates what the unprivileged tasks execute, and nothing else.**
`git` and `curl` are used by `setup`, `fetch` and the Neovim download; `gcc`,
`make`, `ninja` and `msgfmt` by the Neovim build; `flatpak` by `flathub` and
`apps`. `zsh`, `fzf`, `direnv`, `ag`, `kitty` and `pynvim` are excluded: they
are runtime dependencies of the resulting shell, not of any task here. `render`
and `link` write and symlink configuration without invoking any of them, so
blocking on `kitty` would refuse to run on a headless machine for no reason.

**`glibc-gconv-extra` is excluded** because it ships no binary and cannot be
command-checked. `checks-packages.sh` continues to assert it with `rpm -q` in
the privileged phase; its absence otherwise surfaces during the Neovim build.
Putting an `rpm` call in the unprivileged phase would be the only
distribution-specific command outside the dnf declarations.

## 5. Flatpak: user scope, driven directly

Two changes, taken together. The applications move from system scope to user
scope, which is what makes `flathub` and `apps` unprivileged; and they are
installed by calling `flatpak` from the task body rather than through mise's
declarative package table.

```
[tasks.flathub]
depends = ["preflight"]
run = "flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"

[tasks.apps]
depends = ["flathub"]
run = """
set -euo pipefail
for app in <the seventeen identifiers>; do
    flatpak install --user --noninteractive --or-update flathub "$app"
done
"""
```

`--or-update` is load-bearing, not decoration: a plain `flatpak install` on an
application that is already present warns and exits non-zero, which would fail
the second-run requirement (`GEN-R-4`). `--or-update` turns that case into a
silent no-op update.

The remote and the installations must both be user-scope: a system remote is not
visible to a `--user` installation. The two therefore move together and cannot
be split.

`flatpak` the CLI still has to exist. `APPS-A-6` records (VERIFIED) that Flatpak
ships with Fedora Workstation while the Flathub remote does not, so on the
target platform the binary is already present. It stays declared in the
privileged phase's dnf list as a safety net, and preflight checks for it.

### Why the direct command rather than the declarative table

mise does have a user-scope manager. `flatpak-user` was added in mise
v2026.8.3, and the pin in this repository is `2026.8.6`, so it is available -
confirmed against the upstream manager table and the v2026.8.3 release notes.
The choice is therefore not forced; it is a preference for controlling the
invocation directly.

What it costs, recorded honestly:

- `APPS-R-5` requires the list to live in the declarative table and **not** in
  "a separate imperative step with its own wrapper". A `for` loop is exactly
  that, so `APPS-R-5` is withdrawn and replaced (section 7).
- The free `--dry-run` that satisfied `GEN-R-10` for the application step is
  gone and is hand-rolled instead (section 3.4).
- `mise bootstrap packages status` no longer reports on the applications.

What it buys:

- No dependency on mise's Flatpak manager or its argv choices at all.
- Explicit control of `--or-update` and `--noninteractive`, which is what makes
  the step idempotent.
- `APPS-A-2` stops applying. It recorded that mise *skips* Flatpak entries when
  the CLI is absent rather than failing, so a fall-through rule would silently
  install nothing. With the direct command and `flatpak` in preflight's list, an
  absent CLI now blocks loudly before the step runs.

`flatpak install` writes progress to stdout, and this repository otherwise emits
no status output. That is accepted here rather than suppressed: this is a
multi-gigabyte download, and silence during it would be worse than noise.

### Consequences, stated rather than buried

- Roughly 15 GB moves from `/var` into `$HOME`, plus per-user copies of the
  shared runtimes the system installation currently shares.
- The seventeen applications are currently installed system-wide on the author's
  machine. A user-scope run installs a second copy of each rather than adopting
  them, and `flatpak run` prefers user scope, so the system copies become dead
  weight. Removing them is one manual `flatpak uninstall --system`, which needs
  elevation once, outside setup.
- This is the migration `APPS-A-4` was written to avoid. That assumption is not
  wrong - it accurately recorded that system scope matched the pre-migration
  behaviour - but it is no longer the basis for the decision, because removing
  elevation from the default path now outranks matching the old scope.

## 6. Verification harness

### 6.1 Two images

- `test/Containerfile` - unchanged. Bare Fedora plus `sudo`, `git`, `curl` and
  the `NOPASSWD` sudoers entry. Now exercises the privileged phase only.
- `test/Containerfile.nosudo` - **no `sudo` package and no sudoers entry**.
  Fedora plus `git curl gcc make ninja-build gettext glibc-gconv-extra flatpak`
  baked into the image, standing in for a machine on which `./setup system` has
  already run. Exercises everything else.

Baking the prerequisites into the second image is deliberate. It isolates the
property under test - that the unprivileged phase needs no elevation - from the
separate question of whether the privileged phase installs the right things,
which the first image already covers. If any elevation remains in the
unprivileged phase, `sudo` is genuinely absent from the image and the run fails.

### 6.2 Runner signature

```
test/run.sh <check-name> <mise-target> <privileged|unprivileged> [expect-fail]
```

The third argument is mandatory with no default, for the same reason the first
two are: a silently defaulted image would let a check pass against the wrong
machine. The optional fourth argument inverts the expected exit status and
greps the output for the preflight message; under `expect-fail` the setup
command runs once rather than twice, because there is no second run to compare
for idempotence. The named check set is still sourced afterwards, so the
negative run can assert facts about the machine as well as about the failure.

### 6.3 Check assignment

| Check set | Target | Image |
|---|---|---|
| `packages` | `system` | privileged |
| `preflight-missing` | `preflight` | privileged, `expect-fail` |
| `preflight` | `preflight` | unprivileged |
| `bootstrap` | `preview` | unprivileged |
| `tools` | `tools` | unprivileged |
| `fetch` | `fetch` | unprivileged |
| `render` | `render` | unprivileged |
| `link` | `link` | unprivileged |
| `nvim` | `nvim` | unprivileged |
| `apps` | `flathub` | unprivileged |
| `acceptance` | `preview` | unprivileged |

`acceptance` reads the repository rather than the installed system, so its
target is immaterial; `preview` is named because it is the cheapest one.

### 6.4 Check changes

- `checks-apps.sh` flips to user scope throughout: `flatpak remotes --user`,
  the unfiltered-remote assertion against `--user`, and
  `flatpak remote-info --user flathub <app>` for each of the seventeen.
- `checks-packages.sh` is unchanged. It keeps `rpm -q glibc-gconv-extra` and
  `getent passwd tester | grep -q /bin/zsh`, both of which belong to the
  privileged phase.
- `checks-preflight.sh` is new: asserts that preflight succeeded in the
  unprivileged image and that each gated command resolves.
- `checks-preflight-missing.sh` is new, and runs only under `expect-fail` on the
  bare image. `test/run.sh` asserts the non-zero exit and the message; this
  check set asserts that the image really is missing the prerequisites
  (`! command -v gcc` and so on), so the negative test cannot pass for the wrong
  reason.

## 7. Requirement changes

Identifiers are never renumbered. Next free numbers verified against the current
documents: `GEN-R-19`, `APPS-R-10`, `APPS-R-11`.

The citation sweep behind this section is `git grep` over every identifier this
design disturbs, not a reading of the two documents that define them. It found
four locations that a document-by-document reading missed: the verification
table in `tool-desktop-apps.md` section 8, the third scope passage at
`spec-mise-migration.md:491`, the appended-identifier list at
`requirements/README.md:72-73`, and the `APPS-R-6`/`APPS-A-1` citations in
`mise.toml`'s own comments.

### docs/requirements/general.md

- `GEN-A-5` amended in place: sudo is available and interactive **for the
  privileged phase only**. In-place correction rather than withdrawal follows
  the convention already applied to `GEN-A-8`, where observation outranked
  documentation and the identifier kept its number.
- `GEN-R-19` (new): setup SHALL be split into a privileged phase and an
  unprivileged phase. The unprivileged phase SHALL invoke no elevation, and
  SHALL verify its system prerequisites before running any task that needs
  them, failing and naming every absent prerequisite when any is missing.
  Verification: the unprivileged phase completes in an image where `sudo` is not
  installed.

### docs/requirements/tool-desktop-apps.md

- `APPS-R-6` (installed system-wide) **marked withdrawn**, number retired.
- `APPS-R-10` (new): applications SHALL be installed in user scope, so that
  installing them requires no elevation.
- `APPS-R-5` (the list lives in the declarative table, "not in a separate
  imperative step with its own wrapper") **marked withdrawn**, number retired.
  This is the requirement the direct-command decision contradicts head-on.
- `APPS-R-11` (new): the application identifiers SHALL live in `mise.toml` and
  nowhere else, so that `GEN-R-7` (one location for every pin and list) still
  holds once they are no longer in `[bootstrap.packages]`.
- `APPS-R-9` reworded: it currently requires the application step to follow the
  remote step "by applying only the Flatpak entries of the shared table". The
  ordering requirement survives unchanged; the clause about naming the manager
  at apply time is replaced by the direct invocation.
- `APPS-R-7` unchanged in intent - an unfiltered Flathub remote must exist
  before any installation is attempted - with the remote now added `--user`.
- `APPS-A-1` amended: it recorded that the orchestrator's Flatpak manager
  rejects version pins. That no longer describes the mechanism in use.
  `APPS-R-1` (no version pinning) is unaffected, because `flatpak` itself
  exposes no historical-version install either.
- `APPS-A-2` amended: it recorded that mise lists Flatpak entries as *skipped*
  when the CLI is absent, so a fall-through would silently install nothing. That
  failure mode no longer exists here - preflight blocks on an absent `flatpak`.
  The requirement it justifies (`APPS-R-2`, no runtime fallback chain) stands on
  its own remaining grounds and is not withdrawn.
- `APPS-A-4` amended: it recorded that system scope matched the pre-migration
  behaviour. That remains true as a statement about the old setup, and is
  recorded as superseded rather than incorrect.
- `APPS-A-9` amended: its closing condition currently reads "confirmed installed
  and system-scoped". It becomes "user-scoped".
- **Section 8, the verification table** - found by the citation sweep, not by
  reading the prose. Three rows encode the old behaviour and must change:
  `APPS-R-6` ("Installed scope is system-wide for all seventeen"), `APPS-R-9`
  ("applying it names the Flatpak manager only"), and `APPS-A-9` ("confirmed
  installed and system-scoped"). Rows are added for `APPS-R-10` and `APPS-R-11`,
  and the withdrawn `APPS-R-5`/`APPS-R-6` rows removed.

No `APPS-A-10` is written. The earlier draft of this design reserved it for the
`flatpak-user` manager name; driving `flatpak` directly means nothing depends on
that fact, so recording it as a load-bearing assumption would be false. It is
kept only as background in section 5.

### docs/requirements/tool-zsh.md

`ZSH-A-8` and `ZSH-A-9` keep their content unchanged. A sentence is added
recording that the elevation is confined to the privileged phase, so
`ZSH-A-9`'s "asks for elevation on every run" cost now applies to
`./setup system` only, and not to the default `./setup`.

### docs/requirements/README.md

Two edits, both located by the citation sweep:

- Lines 47-50: the paragraph asserting that every assumption is `VERIFIED` and
  that there are no open decisions cites `APPS-A-4` resolving to system-wide. It
  is rewritten to record the scope change. No open assumption replaces it -
  nothing in this design is unverified once `flatpak` is driven directly.
- Lines 72-73: the "New identifiers were appended for behaviour that
  implementation added" list ends with `APPS-R-9` and `APPS-A-9`. `GEN-R-19`,
  `APPS-R-10` and `APPS-R-11` are appended to it, and the withdrawals of
  `APPS-R-5` and `APPS-R-6` are recorded alongside the existing corrections.

### docs/spec-mise-migration.md

Three passages, not two - the third was missed by the original draft of this
design and found by the citation sweep:

- Lines 160-167: the sudo and `[bootstrap.user]` bullets.
- Line 491: "**Scope is system-wide** (APPS-R-6), matching current behaviour, so
  no silent migration of 17 applications between scopes." This is now exactly
  backwards and must be rewritten, including its rationale.
- Lines 607-608: `RR6`, the login-shell elevation note.

Also the section 6 note that both managers' entries share one
`[bootstrap.packages]` table. That stops being true: the table holds `dnf:`
entries only.

`docs/superpowers/plans/2026-08-15-mise-migration.md` is left untouched, as a
dated record of an executed plan.

## 8. Files touched

| File | Change |
|---|---|
| `mise.toml` | Task split, preflight, direct `flatpak` in user scope, preview split, `APPS-R-6`/`APPS-A-1` comments removed |
| `README.md` | Two-command install procedure |
| `test/run.sh` | Third mandatory argument, optional `expect-fail` |
| `test/Containerfile.nosudo` | New |
| `test/checks-preflight.sh` | New |
| `test/checks-preflight-missing.sh` | New |
| `test/checks-apps.sh` | User scope throughout |
| `docs/requirements/general.md` | `GEN-A-5` amended, `GEN-R-19` added |
| `docs/requirements/tool-desktop-apps.md` | `APPS-R-5`/`APPS-R-6` withdrawn, `APPS-R-10`/`APPS-R-11` added, `APPS-R-9` reworded, `APPS-A-1`/`A-2`/`A-4`/`A-9` amended, section 8 verification table updated |
| `docs/requirements/tool-zsh.md` | `ZSH-A-8`/`ZSH-A-9` scoping note |
| `docs/requirements/README.md` | Corrections paragraph and appended-identifier list |
| `docs/spec-mise-migration.md` | Three sudo/scope passages and the shared-table note |

`test/Containerfile` and `test/checks-packages.sh` are unchanged.

## 9. Risk and rollback

Driving `flatpak` directly removed this design's only unverified dependency. The
earlier draft rested on mise's `flatpak-user` manager existing; nothing does
now. What remains are three bounded risks.

**Idempotence of the application step.** `flatpak install --or-update` is
asserted to be a silent no-op on an already-installed application, which is what
`GEN-R-4` requires of a second run. This is the one behaviour in the design that
the harness must actually demonstrate rather than infer, and `test/run.sh`
already runs every target twice, so the existing structure proves it.

If `--or-update` turns out not to be sufficient, the fallback is to test
membership first and skip:

```
installed=$(flatpak list --user --columns=application)
grep -qx "$app" <<<"$installed" || flatpak install --user --noninteractive flathub "$app"
```

**The hand-rolled preview.** `GEN-R-10` is satisfied by a diff rather than by a
supported `--dry-run`, so it can drift from what the install step actually does.
The mitigation is that both read the same identifier list in the same file.

**`APPS-A-9`, unchanged.** It already records that the harness never exercises a
real installation, only resolvability. This design does not close that gap; it
is still closed only by the first run on a real machine.

If the direct command proves unworkable altogether, the ordered fallbacks are:
first mise's `flatpak-user` manager (verified to exist at this pin, restoring
`APPS-R-5` and needing no elevation); and only then reverting to system scope,
which puts `flathub` and `apps` back in `[tasks.system]`, restores `APPS-R-6`,
drops `flatpak` from preflight's list, and returns `checks-apps.sh` to
`--system` on the privileged image. Sections 3 (minus the two tasks), 4, 6 and
the `GEN-R-19` half of section 7 survive either fallback: `./setup` is still
sudo-free, and only the desktop applications would require `./setup system`.

## 10. Success criteria

1. The only `sudo` invocation in `mise.toml` is in `[tasks.login-shell]`, and it
   is reachable only from `[tasks.system]`.
2. `test/run.sh <check> <target> unprivileged` passes for every unprivileged
   check set in an image where `sudo` is not installed.
3. `test/run.sh preflight-missing preflight privileged expect-fail` exits zero,
   having observed a non-zero setup and the missing-commands message.
4. `test/run.sh packages system privileged` passes: dnf packages installed and
   the login shell set.
5. Both `mise run preview` and `mise run preview-system` succeed, `preview` in
   the sudo-less image.
6. Every check set passes on a second consecutive run, unchanged (idempotence,
   `GEN-R-4`). For `apps` this is the specific proof that
   `flatpak install --or-update` is a no-op on an already-installed
   application.
7. `git grep` finds no surviving citation of the withdrawn `APPS-R-5` or
   `APPS-R-6` outside the withdrawal notices themselves and the dated plan
   record.
