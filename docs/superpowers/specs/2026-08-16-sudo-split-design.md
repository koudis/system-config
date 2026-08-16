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
                        mise bootstrap packages apply --dry-run --manager flatpak-user
[tasks.preview-system]  mise run --dry-run system
                        mise bootstrap packages apply --dry-run --manager dnf
```

This split is load-bearing, not cosmetic: `checks-bootstrap.sh` asserts that
`mise run preview` succeeds, and that check now runs inside the sudo-less
image, so `preview` must not reach for dnf.

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

## 5. Flatpak scope

The applications move from system scope to user scope. This is what makes
`flathub` and `apps` unprivileged.

```
sudo flatpak remote-add --if-not-exists flathub ...
  -> flatpak remote-add --user --if-not-exists flathub ...

"flatpak:org.kicad.KiCad" = "latest"   (x17)
  -> "flatpak-user:org.kicad.KiCad" = "latest"

mise bootstrap packages apply --yes --manager flatpak
  -> mise bootstrap packages apply --yes --manager flatpak-user
```

The remote and the installations must both be user-scope: a system remote is not
visible to a `--user` installation. The two therefore move together and cannot
be split.

`flatpak` the CLI still has to exist. `APPS-A-6` records (VERIFIED) that Flatpak
ships with Fedora Workstation while the Flathub remote does not, so on the
target platform the binary is already present. It stays declared in the
privileged phase's dnf list as a safety net, and preflight checks for it.

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
documents: `GEN-R-19`, `APPS-R-10`, `APPS-A-10`.

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
- `APPS-R-7` unchanged in intent - an unfiltered Flathub remote must exist
  before any installation is attempted - with the remote now added `--user`.
- `APPS-A-4` amended: it recorded that system scope matched the pre-migration
  behaviour. That remains true as a statement about the old setup, and is
  recorded as superseded rather than incorrect.
- `APPS-A-9` amended: its closing condition currently reads "confirmed installed
  and system-scoped". It becomes "user-scoped".
- `APPS-A-10` (new): the user-scope manager is named `flatpak-user` and accepts
  a user-scope remote. **Deliberately carries no validation status** until the
  container run observes it, per the convention that an unstatused assumption
  SHALL NOT be relied upon.

### docs/requirements/tool-zsh.md

`ZSH-A-8` and `ZSH-A-9` keep their content unchanged. A sentence is added
recording that the elevation is confined to the privileged phase, so
`ZSH-A-9`'s "asks for elevation on every run" cost now applies to
`./setup system` only, and not to the default `./setup`.

### docs/requirements/README.md

The paragraph asserting that every assumption is `VERIFIED` and that there are
no open decisions cites `APPS-A-4` resolving to system-wide. It is rewritten to
record the scope change, and to list `APPS-A-10` as the one open assumption
until the harness closes it.

### docs/spec-mise-migration.md

The sudo passages at lines 160-167 and 607-608, and the section 6 note that
both managers' entries share one `[bootstrap.packages]` table - still true, but
the manager names change.

`docs/superpowers/plans/2026-08-15-mise-migration.md` is left untouched, as a
dated record of an executed plan.

## 8. Files touched

| File | Change |
|---|---|
| `mise.toml` | Task split, preflight, flatpak-user, preview split |
| `README.md` | Two-command install procedure |
| `test/run.sh` | Third mandatory argument, optional `expect-fail` |
| `test/Containerfile.nosudo` | New |
| `test/checks-preflight.sh` | New |
| `test/checks-preflight-missing.sh` | New |
| `test/checks-apps.sh` | User scope throughout |
| `docs/requirements/general.md` | `GEN-A-5` amended, `GEN-R-19` added |
| `docs/requirements/tool-desktop-apps.md` | `APPS-R-6` withdrawn, `APPS-R-10`/`APPS-A-10` added, `APPS-A-4`/`APPS-A-9` amended |
| `docs/requirements/tool-zsh.md` | `ZSH-A-8`/`ZSH-A-9` scoping note |
| `docs/requirements/README.md` | Open-assumption list |
| `docs/spec-mise-migration.md` | Sudo and manager-name passages |

`test/Containerfile` and `test/checks-packages.sh` are unchanged.

## 9. Risk and rollback

**The one open dependency is `APPS-A-10`.** `flatpak-user` as a manager name is
asserted in a comment at `mise.toml:59` but has never been observed, and mise is
not installed on the development host. It is confirmed or disproved by the first
container run of the `apps` check.

If it is disproved - the manager does not exist under that name, or will not
accept a user-scope remote - the fallback is bounded and does not invalidate the
rest of this design:

- `APPS-R-6` is not withdrawn; `APPS-R-10` and `APPS-A-10` are not added.
- `[tasks.flathub]` and `[tasks.apps]` move back into `[tasks.system]`, keeping
  their `sudo` and their system scope.
- `flatpak` leaves preflight's list.
- `checks-apps.sh` keeps `--system` and runs on the privileged image.
- Sections 3 (minus the two tasks), 4, 6 and the `GEN-R-19` half of section 7
  are unaffected. `./setup` is still sudo-free; desktop applications simply
  require `./setup system`.

A second, smaller risk: `APPS-A-9` already records that the harness never
exercises a real installation, only resolvability. That gap is unchanged by this
design and is still closed only by the first run on a real machine.

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
   `GEN-R-4`).
