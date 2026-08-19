# Privileged/Unprivileged Setup Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `./setup` into a privileged phase that may elevate and an unprivileged phase that never does, and prove the second property in a container where `sudo` is not installed.

**Architecture:** Two aggregate mise tasks behind the single existing `./setup` wrapper. `[tasks.system]` keeps the dnf apply and the `chsh` elevation; `[tasks.all]` runs with none, gated by a new `[tasks.preflight]` that blocks and names any absent prerequisite. The seventeen Flatpak applications move to user scope and are installed by calling `flatpak` directly, which removes the last elevation from the default path.

**Tech Stack:** mise (pinned `2026.8.6`), TOML task definitions, bash task bodies, podman + Fedora 44 containers for verification.

**Spec:** `docs/superpowers/specs/2026-08-16-sudo-split-design.md`

## Global Constraints

- **Fedora is the only target.** No OS conditionals anywhere. `test/checks-acceptance.sh` greps for `OS_NAME|if debian|apt install` and fails the build if any appears outside `docs/`.
- **Pins live in `mise.toml` and nowhere else** (`GEN-R-7`). `min_version = "2026.8.6"` at `mise.toml:5` is read by both mise and `./setup` (via `sed`).
- **No status, progress, debug or informational output** from any script unless required for correctness. Failure messages that name a path or a missing command *are* required for correctness. `flatpak install` progress is the one accepted exception (spec section 5).
- **ASCII only** in every file this plan touches.
- **Requirement identifiers are never renumbered.** A withdrawn requirement is marked withdrawn and its number retired. Next free: `GEN-R-19`, `APPS-R-10`, `APPS-R-11`.
- **The harness clones from HEAD.** `test/run.sh` runs `git clone /home/tester/repo`, which takes committed state only; uncommitted edits to tracked files are dropped on purpose. **Every task must commit before running the harness**, or it tests the previous commit.
- **`test/run.sh` must never default to `all`.** `[tasks.all]` depends on `apps`, which is roughly 15 GB of desktop applications. Every invocation names its target explicitly.
- **The vendored directory is `_vendor/`, not `vendor/`.**
- **podman is required** on the development machine.

---

### Task 1: Commit the pending `_vendor` rename

The working tree carries an uncommitted rename of `vendor/` to `_vendor/` across seven files. Because the harness clones from HEAD, none of the later tasks can be verified until this is committed - the container would keep testing the pre-rename tree while the working copy says otherwise.

**Files:**
- Commit (already modified, do not re-edit): `.gitignore`, `mise.toml`, `test/checks-fetch.sh`, `test/run.sh`, `docs/requirements/README.md`, `docs/requirements/tool-zsh.md`, `docs/spec-mise-migration.md`

- [ ] **Step 1: Confirm exactly these seven files are modified and nothing else**

```bash
git status --short
```

Expected: seven ` M ` lines, exactly the files listed above. If `graphify-out/` appears as untracked, go to Step 2. If any other file is modified, stop and ask.

- [ ] **Step 2: Keep graphify output out of the repository**

`graphify-out/` is generated analysis output, not source. Append to `.gitignore`:

```
graphify-out/
```

- [ ] **Step 3: Verify no `vendor/` reference survives outside vendored trees and the dated plan**

```bash
git grep -n "[^_]vendor/" -- ':!vim/plugin/' ':!docs/superpowers/plans/'
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add .gitignore mise.toml test/checks-fetch.sh test/run.sh \
        docs/requirements/README.md docs/requirements/tool-zsh.md \
        docs/spec-mise-migration.md
git commit -m "refactor: rename vendor/ to _vendor/

Go reserves a top-level vendor directory inside a module and ignores
any directory whose name starts with an underscore. This repository has
no go.mod, so this is naming hygiene rather than a fix.

Migration note for other machines: zsh/zshrc is gitignored and holds
the old path, so [tasks.render]'s overwrite guard will refuse by name.
Delete the generated zsh/zshrc there before re-running."
```

- [ ] **Step 5: Verify the harness now tests the renamed tree**

```bash
test/run.sh fetch fetch
```

Expected: `ALL CHECKS PASSED`, 16/16. This is the last invocation that uses the two-argument signature.

---

### Task 2: Second container image and the mode argument

Give the harness a machine on which `sudo` genuinely does not exist. Nothing in the repository changes behaviour yet - this task only makes the later ones verifiable.

**Files:**
- Create: `test/Containerfile.nosudo`
- Modify: `test/run.sh:1-13` (argument parsing and image selection)

**Interfaces:**
- Produces: `test/run.sh <check-name> <mise-target> <privileged|unprivileged>`. Every later task calls it with three arguments.

- [ ] **Step 1: Write the failing test**

There is no unit-test framework here; the harness itself is the test. Run the new signature before implementing it:

```bash
test/run.sh fetch fetch unprivileged
```

- [ ] **Step 2: Run it to verify it fails**

Expected: the third argument is ignored by the current script, and `podman build` uses `test/Containerfile`, which has `sudo` installed - so this passes for the wrong reason and proves nothing. That is the defect. Confirm `test/Containerfile.nosudo` does not exist:

```bash
test -f test/Containerfile.nosudo && echo EXISTS || echo "ABSENT - as expected"
```

Expected: `ABSENT - as expected`

- [ ] **Step 3: Create `test/Containerfile.nosudo`**

```dockerfile
FROM registry.fedoraproject.org/fedora:44

# The unprivileged phase's prerequisites, baked in: this image stands for a
# machine on which './setup system' has already run, which is what isolates
# "the unprivileged phase needs no elevation" from "the privileged phase
# installs the right things" - the latter is what test/Containerfile covers.
# sudo is deliberately absent, so any elevation left in the unprivileged phase
# fails the run rather than passing silently (GEN-R-19).
RUN dnf -y install git curl gcc make ninja-build gettext glibc-gconv-extra flatpak \
    && dnf clean all
RUN useradd -m tester
USER tester
WORKDIR /home/tester/repo
```

- [ ] **Step 4: Rewrite the head of `test/run.sh`**

Replace lines 1-13 (through the `podman build` call) with:

```bash
#!/usr/bin/env bash
set -euo pipefail
USAGE="usage: test/run.sh <check-name> <mise-target> <privileged|unprivileged> [expect-fail]"
TASK="${1:?$USAGE}"
# No default target: "all" pulls in the apps task, and that is roughly 15 GB of
# desktop applications no check set exercises. Every caller states its target.
TARGET="${2:?$USAGE}"
# No default mode either, for the same reason the target has none: a silently
# defaulted image would let a check pass against the wrong machine.
MODE="${3:?$USAGE}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

case "$MODE" in
    privileged)   CONTAINERFILE="${REPO_ROOT}/test/Containerfile"
                  IMAGE=sysconfig-test ;;
    unprivileged) CONTAINERFILE="${REPO_ROOT}/test/Containerfile.nosudo"
                  IMAGE=sysconfig-test-nosudo ;;
    *)            echo "test/run.sh: mode must be privileged or unprivileged, got '$MODE'" >&2
                  exit 1 ;;
esac

podman build -t "$IMAGE" -f "$CONTAINERFILE" "${REPO_ROOT}"
```

Then change the `podman run` invocation's image name from the literal `sysconfig-test` to `"$IMAGE"`.

- [ ] **Step 5: Verify the mode argument is enforced**

```bash
test/run.sh fetch fetch bogus; echo "exit=$?"
```

Expected: `test/run.sh: mode must be privileged or unprivileged, got 'bogus'` and `exit=1`.

- [ ] **Step 6: Verify both images work**

`fetch` needs only `git` and `curl`, both present in each image, and `[tasks.fetch]` has no `depends`, so it is the one target that runs unchanged in either.

```bash
git add -A && git commit -m "test: add a sudo-less image and require an explicit mode"
test/run.sh fetch fetch privileged
test/run.sh fetch fetch unprivileged
```

Expected: `ALL CHECKS PASSED` from both. The second proves the new image can clone, install mise, and run a task with no `sudo` on the system.

- [ ] **Step 7: Confirm the image really lacks sudo**

```bash
podman run --rm sysconfig-test-nosudo bash -lc 'command -v sudo && echo LEAK || echo "no sudo - correct"'
```

Expected: `no sudo - correct`

- [ ] **Step 8: Commit**

```bash
git add test/Containerfile.nosudo test/run.sh
git commit -m "test: add a sudo-less image and require an explicit mode

The harness ran everything in an image where tester has NOPASSWD:ALL,
so nothing would notice if elevation leaked into a task that must not
elevate. The second image has no sudo package and no sudoers entry, and
bakes in the prerequisites the privileged phase installs, so it stands
for a machine where './setup system' has already run."
```

---

### Task 3: Preflight, and rewiring the unprivileged phase onto it

**Files:**
- Modify: `mise.toml` (add `[tasks.preflight]`; change `depends` on `[tasks.tools]` at line 114 and `[tasks.nvim]` at line 219)
- Create: `test/checks-preflight.sh`

**Interfaces:**
- Produces: `[tasks.preflight]`, which every unprivileged task declares as a dependency in place of `[tasks.packages]`. On failure it exits 1 having written `preflight: missing required commands: <names>` to stderr - `test/run.sh` greps for that exact substring in Task 4.

- [ ] **Step 1: Write the failing check set**

Create `test/checks-preflight.sh`:

```bash
# Preflight gates only what the unprivileged tasks execute. zsh, fzf, direnv,
# ag, kitty and pynvim are deliberately absent from this list: they are runtime
# dependencies of the resulting shell, not of any task here, so blocking on them
# would refuse to run on a headless machine for no reason (spec section 4).
assert_cmd "preflight task exists"    bash -c 'cd /home/tester/work && mise tasks | grep -q preflight'
assert_cmd "git present"              command -v git
assert_cmd "curl present"             command -v curl
assert_cmd "gcc present"              command -v gcc
assert_cmd "make present"             command -v make
assert_cmd "ninja present"            command -v ninja
assert_cmd "msgfmt present"           command -v msgfmt
assert_cmd "flatpak present"          command -v flatpak
# The property under test for the whole unprivileged phase.
assert_cmd "sudo is absent"           bash -c '! command -v sudo'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
git add test/checks-preflight.sh && git commit -m "test: add preflight check set"
test/run.sh preflight preflight unprivileged
```

Expected: failure. `./setup preflight` errors because no task named `preflight` exists.

- [ ] **Step 3: Add `[tasks.preflight]` to `mise.toml`**

Insert immediately before `[tasks.tools]`:

```toml
# The unprivileged phase's system prerequisites. Blocking here rather than
# letting the Neovim build fail on a missing compiler is the same
# refuse-and-name-the-path answer the fetch, render and link guards give: the
# message is the only thing that tells the user the privileged phase was never
# run. Silent on success.
#
# The list gates what the tasks execute and nothing else. git and curl are used
# by setup, fetch and the Neovim download; gcc, make, ninja and msgfmt by the
# Neovim build; flatpak by flathub and apps. glibc-gconv-extra ships no binary
# and cannot be command-checked, so it stays asserted by rpm -q in the
# privileged phase's checks and otherwise surfaces during the build.
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

- [ ] **Step 4: Rewire the two dependencies**

At `[tasks.tools]`, change `depends = ["packages"]` to `depends = ["preflight"]`.

At `[tasks.nvim]`, change `depends = ["tools", "packages", "nvim-stamp"]` to `depends = ["tools", "preflight", "nvim-stamp"]`.

Leave `[tasks.all]` alone for now; Task 5 rewrites it.

- [ ] **Step 5: Run the check set to verify it passes**

```bash
git add mise.toml && git commit -m "feat: gate the unprivileged phase on a preflight check"
test/run.sh preflight preflight unprivileged
```

Expected: `ALL CHECKS PASSED`, 9/9.

- [ ] **Step 6: Verify preflight prints nothing on success**

```bash
podman run --rm -i --security-opt label=disable --userns=keep-id \
    -v "$(git rev-parse --show-toplevel):/home/tester/repo:ro" \
    sysconfig-test-nosudo bash -lc '
        git clone --quiet --no-hardlinks /home/tester/repo /home/tester/work
        cd /home/tester/work && ./setup preflight 2>&1 | grep -c "^preflight:"'
```

Expected: `0`.

- [ ] **Step 7: Commit**

Already committed in Step 5. Confirm the tree is clean:

```bash
git status --short
```

---

### Task 4: The expect-fail mode and the negative preflight test

Prove preflight's failure path on a machine that genuinely lacks the prerequisites. `test/Containerfile` is exactly that machine: it installs only `sudo`, `git` and `curl`.

**Files:**
- Modify: `test/run.sh` (optional fourth argument; conditional setup invocation)
- Create: `test/checks-preflight-missing.sh`

**Interfaces:**
- Consumes: preflight's `preflight: missing required commands:` message from Task 3.
- Produces: `test/run.sh <check> <target> <mode> expect-fail`, which inverts the expected exit status and greps for that message.

- [ ] **Step 1: Write the failing check set**

Create `test/checks-preflight-missing.sh`:

```bash
# Runs only under expect-fail on the bare privileged image. test/run.sh asserts
# the non-zero exit and the message; these assert the image is genuinely missing
# the prerequisites, so the negative test cannot pass for the wrong reason.
assert_cmd "gcc absent"      bash -c '! command -v gcc'
assert_cmd "ninja absent"    bash -c '! command -v ninja'
assert_cmd "msgfmt absent"   bash -c '! command -v msgfmt'
assert_cmd "flatpak absent"  bash -c '! command -v flatpak'
assert_cmd "git present"     command -v git
assert_cmd "curl present"    command -v curl
```

- [ ] **Step 2: Run it to verify it fails**

```bash
git add test/checks-preflight-missing.sh
git commit -m "test: add the bare-image preflight check set"
test/run.sh preflight-missing preflight privileged expect-fail
```

Expected: failure. `test/run.sh` ignores the fourth argument, so `./setup preflight` exits non-zero and `set -e` aborts the whole run before any check is sourced.

- [ ] **Step 3: Add expect-fail handling to `test/run.sh`**

After the `MODE` parse, add:

```bash
EXPECT="${4:-}"
if [ -n "$EXPECT" ] && [ "$EXPECT" != expect-fail ]; then
    echo "test/run.sh: fourth argument must be expect-fail if given, got '$EXPECT'" >&2
    exit 1
fi
```

Pass it into the container by adding `-e EXPECT_FAIL="$EXPECT"` to the `podman run` flags, and replace the two `./setup ${TARGET}` lines in the container script with:

```bash
        if [ \"\$EXPECT_FAIL\" = expect-fail ]; then
            # One run, not two: a failing setup has no second run to compare
            # for idempotence.
            if ./setup ${TARGET} >/tmp/setup.log 2>&1; then
                echo 'FAIL  setup succeeded but expect-fail was requested'; exit 1
            fi
            grep -q 'missing required commands' /tmp/setup.log || {
                echo 'FAIL  setup failed without the preflight message'
                cat /tmp/setup.log
                exit 1
            }
            echo 'PASS  setup failed with the preflight message'
        else
            ./setup ${TARGET}
            echo '--- second run (idempotence) ---'
            ./setup ${TARGET}
        fi
```

- [ ] **Step 4: Run the check set to verify it passes**

```bash
git add test/run.sh && git commit -m "test: add expect-fail mode to the harness"
test/run.sh preflight-missing preflight privileged expect-fail
```

Expected: `PASS  setup failed with the preflight message`, then `ALL CHECKS PASSED`, 6/6.

- [ ] **Step 5: Verify expect-fail actually fails when setup succeeds**

```bash
test/run.sh preflight preflight unprivileged expect-fail; echo "exit=$?"
```

Expected: `FAIL  setup succeeded but expect-fail was requested` and `exit=1`. This proves the inversion is real and not vacuous.

- [ ] **Step 6: Commit**

Already committed in Step 4. Confirm clean:

```bash
git status --short
```

---

### Task 5: Split the privileged phase

**Files:**
- Modify: `mise.toml:80-90` (split `[tasks.packages]`), add `[tasks.system]`, change `[tasks.all]`

**Interfaces:**
- Produces: `[tasks.system]`, the only task from which any elevation is reachable. `[tasks.all]` no longer depends on `packages`.

- [ ] **Step 1: Write the failing check**

Append to `test/checks-packages.sh`:

```bash
assert_cmd "system task exists" bash -c 'cd /home/tester/work && mise tasks | grep -q "^system"'
assert_cmd "login-shell task exists" bash -c 'cd /home/tester/work && mise tasks | grep -q "login-shell"'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
git add test/checks-packages.sh && git commit -m "test: assert the privileged phase is split"
test/run.sh packages system privileged
```

Expected: failure - there is no task named `system`.

- [ ] **Step 3: Split the tasks in `mise.toml`**

Replace the comment block and `[tasks.packages]` at lines 80-90 with:

```toml
# --manager dnf keeps this scoped. The table now holds dnf entries only, so the
# flag is no longer required for correctness; it is kept because it states the
# intent at the call site rather than depending on the table's current contents.
[tasks.packages]
run = "mise bootstrap packages apply --yes --manager dnf"

# chsh authenticates the target user via PAM, which blocks on a password prompt
# for a non-root caller; running it via sudo skips that prompt. sudo's
# secure_path drops $APP_DIR/bin, so PATH must be forwarded explicitly.
# This is the only literal sudo in this file (GEN-R-19); mise elevates on its
# own for the dnf apply above.
[tasks.login-shell]
run = 'sudo env "PATH=$PATH" mise bootstrap user apply --yes'

# The privileged phase. Everything reachable from here may elevate; nothing
# outside it may (GEN-R-19).
[tasks.system]
depends = ["packages", "login-shell"]
```

- [ ] **Step 4: Drop `packages` from the unprivileged aggregate**

Change `[tasks.all]`'s `depends` from
`["packages", "apps", "tools", "fetch", "nvim", "render", "link"]`
to
`["preflight", "apps", "tools", "fetch", "nvim", "render", "link"]`.

- [ ] **Step 5: Run the check set to verify it passes**

```bash
git add mise.toml && git commit -m "feat: split the privileged phase into its own task"
test/run.sh packages system privileged
```

Expected: `ALL CHECKS PASSED`, 11/11 - the nine original assertions plus the two new ones.

- [ ] **Step 6: Verify the elevation is unreachable from the unprivileged aggregate**

```bash
cd "$(git rev-parse --show-toplevel)"
grep -n "sudo" mise.toml | grep -v "^[0-9]*:#"
```

Expected: exactly one line, the `[tasks.login-shell]` `run`.

- [ ] **Step 7: Commit**

Already committed in Step 5.

---

### Task 6: Flatpak in user scope, driven directly

Withdraws `APPS-R-5`. The seventeen identifiers leave `[bootstrap.packages]` and become an `[env]` list read by both the install step and the preview step - one declaration, two readers, which is the same pattern `min_version` already uses.

**Files:**
- Modify: `mise.toml` (remove 17 `flatpak:` keys and the table comment at 58-61; add `FLATPAK_APPS` to `[env]`; rewrite `[tasks.flathub]` and `[tasks.apps]`)
- Modify: `test/checks-apps.sh` (user scope throughout)

**Interfaces:**
- Consumes: `[tasks.preflight]` from Task 3 (`flatpak` is in its gated list).
- Produces: `FLATPAK_APPS`, a whitespace-separated list of seventeen application IDs in `[env]`. Task 7's preview step reads the same variable.

- [ ] **Step 1: Write the failing check set**

Rewrite `test/checks-apps.sh`:

```bash
assert_cmd "flatpak installed"     command -v flatpak
assert_cmd "flathub remote exists" bash -c 'flatpak remotes --user | grep -q flathub'
assert_cmd "flathub is unfiltered" bash -c '! flatpak remotes --user --show-details | grep -qi "filter"'
assert_cmd "no system remote added" bash -c '! flatpak remotes --system | grep -q flathub'
for app in org.kicad.KiCad org.freecad.FreeCAD net.ankiweb.Anki md.obsidian.Obsidian \
           com.prusa3d.PrusaSlicer com.jgraph.drawio.desktop com.usebottles.bottles \
           org.texstudio.TeXstudio org.onlyoffice.desktopeditors org.openstreetmap.josm \
           com.axosoft.GitKraken org.kde.krita com.github.tchx84.Flatseal \
           org.gnome.Extensions com.mattjakeman.ExtensionManager cc.arduino.IDE2 \
           org.kde.tellico; do
    assert_cmd "resolvable: $app" flatpak remote-info --user flathub "$app"
done
```

- [ ] **Step 2: Run it to verify it fails**

```bash
git add test/checks-apps.sh && git commit -m "test: assert flatpak user scope"
test/run.sh apps flathub unprivileged
```

Expected: failure. `[tasks.flathub]` still calls `sudo`, which does not exist in this image.

- [ ] **Step 3: Declare the application list in `[env]`**

Add to `[env]` in `mise.toml`, after the existing pins:

```toml
# The seventeen desktop applications (APPS-R-11: they live here and nowhere
# else, so GEN-R-7 still holds now that they are no longer in
# [bootstrap.packages]). Read by [tasks.apps] and by [tasks.preview].
FLATPAK_APPS = """
org.kicad.KiCad org.freecad.FreeCAD net.ankiweb.Anki md.obsidian.Obsidian
com.prusa3d.PrusaSlicer com.jgraph.drawio.desktop com.usebottles.bottles
org.texstudio.TeXstudio org.onlyoffice.desktopeditors org.openstreetmap.josm
com.axosoft.GitKraken org.kde.krita com.github.tchx84.Flatseal
org.gnome.Extensions com.mattjakeman.ExtensionManager cc.arduino.IDE2
org.kde.tellico
"""
```

- [ ] **Step 4: Delete the Flatpak entries from `[bootstrap.packages]`**

Remove the comment block at lines 58-61 and all seventeen `"flatpak:..." = "latest"` lines. The table keeps its fourteen `dnf:` entries and nothing else.

- [ ] **Step 5: Rewrite the two tasks**

```toml
# mise does not create flatpak remotes (APPS-A-5), so this is an explicit
# preceding step (APPS-R-7). Adding the remote manually, rather than via
# Fedora's flatpak-remote package, is what removes Fedora's default filter
# (APPS-A-7). --if-not-exists makes it idempotent (APPS-R-8), and --user is
# what removes the elevation: a system remote is not visible to a --user
# install, so the remote and the installs must share a scope.
[tasks.flathub]
depends = ["preflight"]
run = """
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
"""

# --or-update is load-bearing: a plain install on an application that is
# already present warns and exits non-zero, which would fail the second-run
# requirement (GEN-R-4). --or-update makes that case a silent no-op update.
# flatpak's own progress output is the one place this repository emits status;
# suppressing it during a multi-gigabyte download would be worse than the noise.
[tasks.apps]
depends = ["flathub"]
run = """
set -euo pipefail
for app in $FLATPAK_APPS; do
    flatpak install --user --noninteractive --or-update flathub "$app"
done
"""
```

- [ ] **Step 6: Run the check set to verify it passes**

```bash
git add mise.toml test/checks-apps.sh
git commit -m "feat: install flatpaks in user scope with the flatpak command"
test/run.sh apps flathub unprivileged
```

Expected: `ALL CHECKS PASSED`, 21/21. The `flathub` target adds the remote and resolves all seventeen without elevation, in an image with no `sudo`.

- [ ] **Step 7: Verify the second run is a no-op**

The harness already runs the target twice. Confirm the idempotence banner appears and nothing after it errors:

```bash
test/run.sh apps flathub unprivileged 2>&1 | grep -A3 "second run"
```

Expected: the banner followed by no error.

- [ ] **Step 8: Commit**

Already committed in Step 6.

---

### Task 7: Split the preview

`checks-bootstrap.sh` asserts `mise run preview` succeeds, and that check now runs in the sudo-less image, so `preview` must not reach for dnf.

**Files:**
- Modify: `mise.toml:335-341` (`[tasks.preview]`), add `[tasks.preview-system]`

**Interfaces:**
- Consumes: `FLATPAK_APPS` from Task 6.

- [ ] **Step 1: Write the failing check**

Append to `test/checks-bootstrap.sh`:

```bash
assert_cmd "preview-system mode runs" bash -c 'cd /home/tester/work && mise run preview-system'
assert_cmd "preview names no dnf"     bash -c '! grep -A5 "^\[tasks.preview\]$" /home/tester/work/mise.toml | grep -q "manager dnf"'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
git add test/checks-bootstrap.sh && git commit -m "test: assert the preview is split"
test/run.sh bootstrap preview unprivileged
```

Expected: failure - no task named `preview-system`, and the current `preview` names `--manager dnf`.

- [ ] **Step 3: Rewrite the preview tasks**

Replace `[tasks.preview]` with:

```toml
# GEN-R-10 requires a mode that reports what would change without changing it.
# Split along the same seam as the phases: this one must stay runnable where
# sudo does not exist, which is where checks-bootstrap.sh now exercises it.
# The application half is hand-rolled because driving flatpak directly costs
# the --dry-run the declarative table would have provided; it reads the same
# FLATPAK_APPS list the install step reads.
[tasks.preview]
run = """
set -euo pipefail
mise run --dry-run all
installed=$(flatpak list --user --columns=application 2>/dev/null || true)
for app in $FLATPAK_APPS; do
    grep -qx "$app" <<<"$installed" || echo "would install: $app"
done
"""

[tasks.preview-system]
run = """
mise run --dry-run system
mise bootstrap packages apply --dry-run --manager dnf
"""
```

- [ ] **Step 4: Run the check set to verify it passes**

```bash
git add mise.toml && git commit -m "feat: split preview along the privilege seam"
test/run.sh bootstrap preview unprivileged
```

Expected: `ALL CHECKS PASSED`, 9/9.

- [ ] **Step 5: Verify the preview changes nothing**

```bash
test/run.sh apps preview unprivileged
```

Expected: failure on `flathub remote exists` - `preview` must not have created the remote. That failure is the proof; note it and move on.

- [ ] **Step 6: Commit**

Already committed in Step 4.

---

### Task 8: Documentation and requirements

Every edit below was located by `git grep` over the disturbed identifiers. Four of them were missed by a document-by-document reading, so do not skip the sweep in Step 1.

**Files:**
- Modify: `README.md:19-33`
- Modify: `docs/requirements/general.md:125` (`GEN-A-5`), and the requirements table near line 373 (`GEN-R-19`)
- Modify: `docs/requirements/tool-desktop-apps.md` (lines 21, 46, 78, 87, 94, 132, 140, and the section 8 table at 167-176)
- Modify: `docs/requirements/tool-zsh.md:113-124`
- Modify: `docs/requirements/README.md:47-50` and `:72-73`
- Modify: `docs/spec-mise-migration.md:160-167`, `:491`, `:607-608`

- [ ] **Step 1: Take the citation sweep as your worklist**

```bash
cd "$(git rev-parse --show-toplevel)"
for id in APPS-R-5 APPS-R-6 APPS-R-9 APPS-A-1 APPS-A-2 APPS-A-4 APPS-A-9 GEN-A-5; do
  echo "=== $id ==="
  git grep -n -- "$id" -- ':!docs/superpowers/'
done
```

Every line printed is either edited below or deliberately left alone. Nothing else.

- [ ] **Step 2: Rewrite the README install procedure**

Replace the `## Build and Install` code block and the `sudo -v` paragraph:

````markdown
```bash
sudo -v
./setup system
./setup
```

`./setup system` is the privileged half and is run once per machine. It installs
the distribution packages and sets the login shell, and it is the only command
here that elevates. `./setup` is the whole rest of the work and never elevates -
it refuses to start if the privileged half has not run, naming what is missing.

Refresh the sudo credential first, as shown, before `./setup system`. Package
installation and the login shell change run as tasks, and mise interleaves task
output, so a password prompt appearing from inside a task is unprefixed and easy
to miss among the other lines.
````

- [ ] **Step 3: Amend `GEN-A-5` and add `GEN-R-19`**

`docs/requirements/general.md:125` becomes:

```markdown
**GEN-A-5 `sudo` is available and interactive during the privileged phase.**
System package installation requires elevation and the user is present to
authorise it. This holds for the privileged phase only; the unprivileged phase
requires no elevation and is verified where `sudo` is not installed (GEN-R-19).
`VERIFIED`.
```

Add after `GEN-R-18`:

```markdown
**GEN-R-19** Setup SHALL be split into a privileged phase and an unprivileged
phase. The unprivileged phase SHALL invoke no elevation, and SHALL verify its
system prerequisites before running any task that needs them, failing and naming
every absent prerequisite when any is missing.
```

Add to the requirements table near line 373:

```markdown
| GEN-R-19 | The unprivileged phase completes in an image where sudo is not installed |
```

- [ ] **Step 4: Apply the desktop-apps changes**

- `APPS-R-5` (line 78): prefix the statement with `**WITHDRAWN.**` and add: `Withdrawn because the applications are installed by calling flatpak directly rather than through the declarative table; replaced by APPS-R-11.`
- `APPS-R-6` (line 87): same treatment. `Withdrawn in favour of APPS-R-10: system scope is what required elevation.`
- Add after `APPS-R-9`:

```markdown
**APPS-R-10** Applications SHALL be installed in user scope, so that installing
them requires no elevation (GEN-R-19).

**APPS-R-11** The application identifiers SHALL live in `mise.toml` and nowhere
else, so that GEN-R-7 continues to hold now that they are not declared in
`[bootstrap.packages]`.
```

- `APPS-R-9` (line 132): keep the ordering requirement; replace the clause about naming the manager at apply time with the direct invocation.
- `APPS-A-1` (line 21): add `This no longer describes the mechanism in use - applications are installed by calling flatpak directly. APPS-R-1 is unaffected: flatpak exposes no historical-version install either.`
- `APPS-A-2` (line 46): add `This failure mode no longer exists here: preflight blocks on an absent flatpak before the step runs. APPS-R-2 stands on its remaining grounds.`
- `APPS-A-4` (line 94): add `Superseded, not incorrect: removing elevation from the default path now outranks matching the pre-migration scope.`
- `APPS-A-9` (line 140): change `system-scope Flatpak install` to `user-scope Flatpak install`.
- Section 8 table (167-176): drop the `APPS-R-5` and `APPS-R-6` rows, change the `APPS-R-9` row to drop "and applying it names the Flatpak manager only", change the `APPS-A-9` row's tail from `system-scoped` to `user-scoped`, and add:

```markdown
| APPS-R-10 | Installed scope is user for all seventeen, and no system remote is added |
| APPS-R-11 | The seventeen identifiers appear in mise.toml and in no other tracked file |
```

- [ ] **Step 5: Add the zsh scoping note**

After `ZSH-A-9` in `docs/requirements/tool-zsh.md`, add:

```markdown
The elevation is confined to the privileged phase (GEN-R-19), so this cost
applies to `./setup system` only and not to the default `./setup`.
```

- [ ] **Step 6: Update the requirements index**

`docs/requirements/README.md:47-50`: rewrite the `APPS-A-4` bullet to record that scope changed to user, and drop the claim that it closed the decision.

`docs/requirements/README.md:72-73`: append `GEN-R-19`, `APPS-R-10` and `APPS-R-11` to the new-identifier list, and add a line recording that `APPS-R-5` and `APPS-R-6` are withdrawn.

- [ ] **Step 7: Update the migration spec's three passages**

- Lines 160-167: scope the sudo bullet to the privileged phase.
- Line 491: replace `**Scope is system-wide** (APPS-R-6), matching current behaviour, so no silent migration of 17 applications between scopes.` with a statement of user scope under `APPS-R-10`, recording that the scope migration is accepted deliberately because it removes elevation from the default path.
- Lines 607-608: note that `RR6`'s per-run elevation applies to `./setup system` only.
- The section 6 note that both managers share one `[bootstrap.packages]` table: the table now holds `dnf:` entries only.

- [ ] **Step 8: Verify no stale citation survives**

```bash
git grep -n -- "APPS-R-6" -- ':!docs/superpowers/plans/'
git grep -n -- "APPS-R-5" -- ':!docs/superpowers/plans/'
```

Expected: only the withdrawal notices in `tool-desktop-apps.md`, the withdrawal record in `requirements/README.md`, and the design spec.

- [ ] **Step 9: Verify ASCII and the acceptance checks**

```bash
LC_ALL=C grep -rn '[^ -~]' README.md docs/requirements/ docs/spec-mise-migration.md
git add -A && git commit -m "docs: record the privileged/unprivileged split"
test/run.sh acceptance preview unprivileged
```

Expected: no non-ASCII output, then `ALL CHECKS PASSED`.

---

### Task 9: Full regression

**Files:** none modified. This task only runs the suite.

- [ ] **Step 1: Confirm the tree is committed**

```bash
git status --short
```

Expected: empty. The harness clones from HEAD, so anything uncommitted is invisible to every run below.

- [ ] **Step 2: Run the privileged sets**

```bash
test/run.sh packages system privileged
test/run.sh preflight-missing preflight privileged expect-fail
```

- [ ] **Step 3: Run the unprivileged sets**

```bash
test/run.sh preflight  preflight unprivileged
test/run.sh bootstrap  preview   unprivileged
test/run.sh acceptance preview   unprivileged
test/run.sh fetch      fetch     unprivileged
test/run.sh render     render    unprivileged
test/run.sh link       link      unprivileged
test/run.sh tools      tools     unprivileged
test/run.sh nvim       nvim      unprivileged
test/run.sh apps       flathub   unprivileged
```

Expected: `ALL CHECKS PASSED` from each. Every one of these ran in an image with no `sudo` installed, which is the whole point of the change.

- [ ] **Step 4: Verify the success criteria from spec section 10**

```bash
cd "$(git rev-parse --show-toplevel)"
grep -n "sudo" mise.toml | grep -v "^[0-9]*:#"
```

Expected: one line, `[tasks.login-shell]`'s `run`.

- [ ] **Step 5: Report what the harness cannot close**

`APPS-A-9` still holds: the container proves the remote exists, is unfiltered, and resolves all seventeen identifiers - not that they install. A real installation needs a session bus the sandboxed container does not have. State this in the completion report rather than claiming the applications are verified.

---

## Self-Review

**Spec coverage.** Section 3.1 -> Task 5. Section 3.2 -> Tasks 3, 5, 6. Section 3.3 -> Task 8 Step 2. Section 3.4 -> Task 7. Section 4 -> Task 3. Section 5 -> Task 6. Section 6.1 -> Task 2. Section 6.2 -> Tasks 2 and 4. Section 6.3 -> Task 9. Section 6.4 -> Tasks 3, 4, 6. Section 7 -> Task 8. Section 8 -> all. Section 9 -> Task 6 Step 7 (idempotence), Task 7 (preview drift), Task 9 Step 5 (`APPS-A-9`). Section 10 -> Task 9.

**Prerequisite not in the spec:** Task 1 exists because the harness clones from HEAD and the working tree carried an uncommitted rename. Without it every later verification tests the wrong tree.

**Refinement to the spec:** the spec wrote the seventeen identifiers inline in `[tasks.apps]`. Task 6 puts them in `[env].FLATPAK_APPS` instead, because Task 7's preview needs the same list and duplicating it would leave two lists to drift apart. This satisfies `APPS-R-11` as written - `mise.toml` and nowhere else.

**Type consistency.** `FLATPAK_APPS` is declared in Task 6 Step 3 and consumed in Task 6 Step 5 and Task 7 Step 3. Task names are stable throughout: `preflight`, `packages`, `login-shell`, `system`, `flathub`, `apps`, `tools`, `fetch`, `nvim-stamp`, `nvim`, `render`, `link`, `all`, `preview`, `preview-system`. Check-set names match their files: `preflight` -> `test/checks-preflight.sh`, `preflight-missing` -> `test/checks-preflight-missing.sh`. The harness signature `<check-name> <mise-target> <privileged|unprivileged> [expect-fail]` is introduced in Task 2, extended in Task 4, and used consistently after.
