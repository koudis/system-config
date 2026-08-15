# mise Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace 14 shell scripts and 9 git submodules with a single repo-root `mise.toml` plus a thin bootstrap wrapper, so a fresh Fedora notebook is configured by one idempotent command.

**Architecture:** `mise` is the sole orchestrator. A repo-root `mise.toml` holds every version pin and every task, wired by declared `depends`. A `./setup` wrapper exports the application-directory variables that mise reads at process start and cannot set itself, then runs the task graph. The repository owns configuration, templates, pins and vendored runtime content; a configurable application directory (default `~/App`) owns every installed binary.

**Tech Stack:** mise (orchestrator, task runner, tool manager), dnf, flatpak, git, bash, sed. No Python, no Ansible, no Nix.

**Spec:** `docs/spec-mise-migration.md`. Requirements it implements: `docs/requirements/general.md` and `docs/requirements/tool-*.md`. Procedure for later additions: `docs/adding-a-new-tool.md`.

## Global Constraints

Copied verbatim from the spec and requirements. Every task's requirements implicitly include this section.

- **Fedora only** (GEN-A-2). No operating-system conditionals anywhere (GEN-R-8). Package names are Fedora names only.
- **Application directory** default `~/App`, overridable by `APP_DIR` (GEN-R-1b). Referenced by variable, never by literal path. All installed artifacts go there and nowhere else (GEN-R-1a). No second install prefix - `$HOME/Bin` is retired.
- **`MISE_DATA_DIR` is read at process start** and cannot be set from `[env]` (GEN-A-7). Only `./setup` may export it.
- **Every source URL is anonymous HTTPS** (GEN-A-4). No `git@github.com:` URLs.
- **Every pin lives in `mise.toml` and nowhere else** (GEN-R-7). No shell constants, no gitlinks, no template values.
- **Idempotent**: two consecutive runs, second one does nothing and exits zero (GEN-R-4).
- **Pinned versions**: Neovim `v0.11.6` built `RelWithDebInfo`; CMake `3.30.1`; Go `1.23.3`.
- **ohmyzsh is a git clone, never an archive** (ZSH-R-2), created under `umask g-w,o-w` (ZSH-R-3).
- **Flatpaks are system-wide** (APPS-R-6) and the Flathub remote must be established first (APPS-R-7) - mise will not create it.
- **Documentation is normative.** Adding anything without its requirements document is incomplete work (GEN-R-13).

**Executor prerequisite:** `podman` must be installed on the development machine. Task 1 builds the verification harness on it, and every later task is tested through that harness rather than against your real workstation. Install with `sudo dnf install -y podman` before starting.

---

### Task 1: Verification harness

Nothing else in this plan is safely testable without this. Every later task runs its checks inside a throwaway Fedora container, never against the real machine.

**Files:**
- Create: `test/Containerfile`
- Create: `test/run.sh`
- Create: `test/assert.sh`

**Interfaces:**
- Produces: `test/run.sh <task-name>` builds a clean Fedora container, copies the repo in, runs `./setup`, and executes `test/assert.sh <task-name>`. Exit 0 means pass.
- Produces: `assert_cmd <description> <command>` and `assert_path_under <description> <binary> <prefix>` shell functions, sourced by later tasks.

- [ ] **Step 1: Write the failing harness invocation**

Create `test/assert.sh`:

```bash
#!/usr/bin/env bash
# Assertion helpers. Sourced by the in-container test run.
FAILED=0

assert_cmd() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf 'PASS  %s\n' "$desc"
    else
        printf 'FAIL  %s  (command: %s)\n' "$desc" "$*"; FAILED=1
    fi
}

assert_path_under() {
    local desc="$1" binary="$2" prefix="$3"
    local resolved; resolved=$(command -v "$binary" 2>/dev/null)
    if [[ -n $resolved && $resolved == "$prefix"* ]]; then
        printf 'PASS  %s (%s)\n' "$desc" "$resolved"
    else
        printf 'FAIL  %s  (%s resolved to %s, expected under %s)\n' \
            "$desc" "$binary" "${resolved:-<not found>}" "$prefix"; FAILED=1
    fi
}

assert_absent() {
    local desc="$1" pattern="$2" file="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        printf 'FAIL  %s  (%s still present in %s)\n' "$desc" "$pattern" "$file"; FAILED=1
    else
        printf 'PASS  %s\n' "$desc"
    fi
}

finish() { [[ $FAILED -eq 0 ]] && printf '\nALL CHECKS PASSED\n' || printf '\nCHECKS FAILED\n'; exit $FAILED; }
```

- [ ] **Step 2: Write the container definition**

Create `test/Containerfile`:

```dockerfile
FROM registry.fedoraproject.org/fedora:44

# Only what a genuinely fresh Fedora install has, plus sudo and git so the
# harness can copy the repo in and run setup as a non-root user. Deliberately
# NOT installing build tooling: Task 7 must prove it declares its own.
RUN dnf -y install sudo git curl && dnf clean all
RUN useradd -m tester && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
USER tester
WORKDIR /home/tester/repo
```

- [ ] **Step 3: Write the runner**

Create `test/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
TASK="${1:?usage: test/run.sh <task-name>}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

podman build -t sysconfig-test -f "${REPO_ROOT}/test/Containerfile" "${REPO_ROOT}"

podman run --rm -i \
    -v "${REPO_ROOT}:/home/tester/repo:ro,Z" \
    sysconfig-test bash -lc "
        set -euo pipefail
        cp -a /home/tester/repo /home/tester/work
        cd /home/tester/work
        ./setup
        echo '--- second run (idempotence) ---'
        ./setup
        source test/assert.sh
        source test/checks-${TASK}.sh
        finish
    "
```

- [ ] **Step 4: Verify the harness fails correctly**

Run: `chmod +x test/run.sh && test/run.sh smoke`

Expected: FAIL - the container builds, but `./setup` does not exist yet. This proves the harness reaches the right point and does not silently pass.

- [ ] **Step 5: Commit**

```bash
git add test/
git commit -m "test: add containerised verification harness"
```

---

### Task 2: Bootstrap wrapper and mise.toml skeleton

**Files:**
- Create: `setup` (executable)
- Create: `mise.toml`
- Modify: `.gitignore`
- Create: `test/checks-bootstrap.sh`

**Interfaces:**
- Consumes: `test/assert.sh` from Task 1.
- Produces: `$APP_DIR` (default `~/App`) and `$MISE_DATA_DIR` (`$APP_DIR/mise`) exported into every task. Produces the `all` task name that later tasks attach to via `depends`.

- [ ] **Step 1: Write the failing check**

Create `test/checks-bootstrap.sh`:

```bash
assert_cmd  "mise is installed"            command -v mise
assert_cmd  "APP_DIR exists"               test -d "${APP_DIR:-$HOME/App}"
assert_cmd  "MISE_DATA_DIR under APP_DIR"  test -d "${APP_DIR:-$HOME/App}/mise"
assert_cmd  "no legacy Bin prefix"         test ! -d "$HOME/Bin"
assert_cmd  "mise finds repo config"       bash -c 'cd /home/tester/work && mise config ls | grep -q mise.toml'
assert_cmd  "preview mode runs"            bash -c 'cd /home/tester/work && mise run preview'
assert_cmd  "cmakelib env exported"        bash -c 'cd /home/tester/work && mise env | grep -q CMLIB_DIR'
```

- [ ] **Step 2: Run it to confirm failure**

Run: `test/run.sh bootstrap`
Expected: FAIL - `./setup` does not exist.

- [ ] **Step 3: Write the wrapper**

Create `setup`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# APP_DIR and MISE_DATA_DIR are read by mise at process start and cannot be
# set from mise.toml's [env] (GEN-A-7). This wrapper exists to export them.
export APP_DIR="${APP_DIR:-$HOME/App}"
export MISE_DATA_DIR="$APP_DIR/mise"

mkdir -p "$APP_DIR" "$MISE_DATA_DIR"

if ! command -v mise >/dev/null 2>&1; then
    # MISE_INSTALL_PATH must name a file, not a directory; the installer
    # errors out if given a directory.
    curl -fsSL https://mise.run | MISE_INSTALL_PATH="$APP_DIR/bin/mise" sh
    export PATH="$APP_DIR/bin:$PATH"
fi

# mise refuses to load an untrusted config file. Without this, the first run on
# a fresh machine either prompts or does nothing.
mise trust "$(git rev-parse --show-toplevel)/mise.toml"

exec mise run "${@:-all}"
```

- [ ] **Step 4: Write the mise.toml skeleton**

Create `mise.toml`. Every pin in this repository lives in this file (GEN-R-7):

```toml
[settings]
experimental = true

[settings.task]
source_freshness_hash_contents = true

[env]
# --- pins: the single location (GEN-R-7) ---
NVIM_VERSION       = "v0.11.6"
OHMYZSH_REF        = "b54a71977574cfcf659cc2f15a5e6422f17a8da7"
AUTOSUGGEST_REF    = "c3d4e576c9c86eac62884bd47c01f6faed043fc5"
CMLIB_REF          = "3bd355abf81081dd90ff49728f7629ea340357ec"
CMLIB_CMCONF_REF   = "v1.2.1"
CMLIB_CMDEF_REF    = "v1.0.3"
CMLIB_CMUTIL_REF   = "66ea4a90adfe67567006e09b26122f370eeb2066"
CMLIB_STORAGE_REF  = "f4080a0e6e8a47831f04bbd371871fecaf5d9560"

# cmakelib's own outputs (CMLIB-R-2), declared here rather than emitted from
# the shell template. This is what removes the hidden coupling flagged by
# GEN-R-9, ZSH-R-9 and CMLIB-R-3.
CMLIB_DIR                       = "{{config_root}}/vendor/cmakelib"
CMLIB_COMPONENT_LOCAL_BASE_PATH = "{{config_root}}/vendor/"

[tools]
cmake = "3.30.1"
go    = "1.23.3"

[tasks.all]
depends = ["link", "nvim", "apps"]
run = "echo setup complete"

# GEN-R-10 requires a mode that reports what would change without changing it.
[tasks.preview]
run = """
mise run --dry-run all
mise system install --dry-run
""""
```

- [ ] **Step 5: Update .gitignore**

Modify `.gitignore` to append:

```
.build/
vendor/
zsh/zshrc
zsh/config
vim/init.vim
```

- [ ] **Step 6: Run the check**

Run: `chmod +x setup && test/run.sh bootstrap`
Expected: PASS on all five assertions.

- [ ] **Step 7: Commit**

```bash
git add setup mise.toml .gitignore test/checks-bootstrap.sh
git commit -m "feat: add mise bootstrap wrapper and pin file"
```

---

### Task 3: System packages

**Files:**
- Modify: `mise.toml`
- Create: `test/checks-packages.sh`

**Interfaces:**
- Consumes: the `mise.toml` skeleton from Task 2.
- Produces: task name `packages`, which later tasks declare in `depends`.

- [ ] **Step 1: Write the failing check**

Create `test/checks-packages.sh`:

```bash
assert_cmd "zsh installed"            command -v zsh
assert_cmd "fzf installed"            command -v fzf
assert_cmd "direnv installed"         command -v direnv
assert_cmd "ag installed"             command -v ag
assert_cmd "pynvim module present"    python3 -c 'import pynvim'
assert_cmd "ninja-build installed"    command -v ninja
assert_cmd "gettext installed"        command -v msgfmt
assert_cmd "glibc-gconv-extra"        rpm -q glibc-gconv-extra
assert_cmd "login shell is zsh"       bash -c 'getent passwd tester | grep -q /bin/zsh'
```

Note the correct package names (GEN-R-14): `the_silver_searcher` provides `ag`, and `python3-neovim` provides the `pynvim` module. The repo currently declares `ag` and `python-neovim`, neither of which is installable.

- [ ] **Step 2: Run it to confirm failure**

Run: `test/run.sh packages`
Expected: FAIL - none of these are installed.

- [ ] **Step 3: Determine which config key this mise supports**

`[system]` is experimental and upstream is mid-rename (GEN-A-8). Before writing the config, find out which spelling the installed version accepts:

```bash
mise system --help 2>/dev/null && echo "USE [system.packages]"
mise bootstrap packages --help 2>/dev/null && echo "USE [bootstrap.packages]"
```

Use whichever responds. If neither does, skip to Step 5 (the fallback).

- [ ] **Step 4: Add the declarative system packages**

Append to `mise.toml`, using the section name discovered in Step 3:

```toml
[system]
login_shell = "zsh"

[system.packages]
"dnf:zsh"                 = "latest"
"dnf:direnv"              = "latest"
"dnf:fzf"                 = "latest"
"dnf:the_silver_searcher" = "latest"
"dnf:kitty"               = "latest"
"dnf:python3-neovim"      = "latest"
# Neovim build prerequisites, verbatim from upstream (GEN-A-10)
"dnf:ninja-build"         = "latest"
"dnf:gcc"                 = "latest"
"dnf:make"                = "latest"
"dnf:gettext"             = "latest"
"dnf:curl"                = "latest"
"dnf:glibc-gconv-extra"   = "latest"
"dnf:git"                 = "latest"

[tasks.packages]
run = "mise system install --yes"
```

- [ ] **Step 5: Fallback if the experimental subsystem is unusable**

Only if Step 3 found nothing. Replace the `[system.packages]` block and the `packages` task with a single task holding the same list - the OS branching still disappears, because Fedora is the only target (GEN-R-8):

```toml
[tasks.packages]
run = """
sudo dnf install -y \
  zsh direnv fzf the_silver_searcher kitty python3-neovim \
  ninja-build gcc make gettext curl glibc-gconv-extra git
sudo chsh -s "$(command -v zsh)" "$USER"
"""
```

- [ ] **Step 6: Run the check**

Run: `test/run.sh packages`
Expected: PASS on all nine assertions.

- [ ] **Step 7: Commit**

```bash
git add mise.toml test/checks-packages.sh
git commit -m "feat: declare Fedora system packages and build prerequisites"
```

---

### Task 4: Flathub remote and desktop applications

**Files:**
- Modify: `mise.toml`
- Create: `test/checks-apps.sh`

**Interfaces:**
- Consumes: task `packages` from Task 3.
- Produces: task names `flathub` and `apps`.

The container cannot run graphical applications, so these checks verify that the remote is established and that `flatpak` resolves each application ID - not that the apps launch.

- [ ] **Step 1: Write the failing check**

Create `test/checks-apps.sh`:

```bash
assert_cmd "flatpak installed"        command -v flatpak
assert_cmd "flathub remote exists"    bash -c 'flatpak remotes --system | grep -q flathub'
assert_cmd "flathub is unfiltered"    bash -c '! flatpak remotes --system --show-details | grep -qi "filter"'
for app in org.kicad.KiCad org.freecad.FreeCAD net.ankiweb.Anki md.obsidian.Obsidian \
           com.prusa3d.PrusaSlicer com.jgraph.drawio.desktop com.usebottles.bottles \
           org.texstudio.TeXstudio org.onlyoffice.desktopeditors org.openstreetmap.josm \
           com.axosoft.GitKraken org.kde.krita com.github.tchx84.Flatseal \
           org.gnome.Extensions com.mattjakeman.ExtensionManager cc.arduino.IDE2 \
           org.kde.tellico; do
    assert_cmd "resolvable: $app" flatpak remote-info --system flathub "$app"
done
```

- [ ] **Step 2: Run it to confirm failure**

Run: `test/run.sh apps`
Expected: FAIL - no flatpak, no remote.

- [ ] **Step 3: Add the remote task**

mise does not create remotes (APPS-A-5), so this is an explicit preceding step. Append to `mise.toml`:

```toml
[tasks.flathub]
depends = ["packages"]
run = """
sudo flatpak remote-add --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
"""
```

Adding the remote manually is what removes Fedora's filter (APPS-A-7). `--if-not-exists` makes it idempotent (APPS-R-8).

- [ ] **Step 4: Add flatpak to the package list and the apps task**

Add `"dnf:flatpak" = "latest"` to the `[system.packages]` block from Task 3, then append:

```toml
[system.packages]
"flatpak:org.kicad.KiCad"              = "latest"
"flatpak:org.freecad.FreeCAD"          = "latest"
"flatpak:net.ankiweb.Anki"             = "latest"
"flatpak:md.obsidian.Obsidian"         = "latest"
"flatpak:com.prusa3d.PrusaSlicer"      = "latest"
"flatpak:com.jgraph.drawio.desktop"    = "latest"
"flatpak:com.usebottles.bottles"       = "latest"
"flatpak:org.texstudio.TeXstudio"      = "latest"
"flatpak:org.onlyoffice.desktopeditors" = "latest"
"flatpak:org.openstreetmap.josm"       = "latest"
"flatpak:com.axosoft.GitKraken"        = "latest"
"flatpak:org.kde.krita"                = "latest"
"flatpak:com.github.tchx84.Flatseal"   = "latest"
"flatpak:org.gnome.Extensions"         = "latest"
"flatpak:com.mattjakeman.ExtensionManager" = "latest"
"flatpak:cc.arduino.IDE2"              = "latest"
"flatpak:org.kde.tellico"              = "latest"

[tasks.apps]
depends = ["flathub"]
run = "mise system install --yes --manager flatpak"
```

`flatpak` (not `flatpak-user`) is system scope (APPS-R-6). `"latest"` is mandatory - the manager rejects version pins (APPS-A-1).

- [ ] **Step 5: Run the check**

Run: `test/run.sh apps`
Expected: PASS. If `remote-info` fails for an application, that ID has changed upstream - correct it in both `mise.toml` and `docs/requirements/tool-desktop-apps.md`.

- [ ] **Step 6: Commit**

```bash
git add mise.toml test/checks-apps.sh
git commit -m "feat: establish Flathub remote and declare 17 desktop applications"
```

---

### Task 5: Dev tools under the application directory

**Files:**
- Modify: `mise.toml`
- Create: `test/checks-tools.sh`

**Interfaces:**
- Consumes: `[tools]` block from Task 2, task `packages` from Task 3.
- Produces: `cmake` and `go` binaries under `$APP_DIR`, relied on by Task 7.

- [ ] **Step 1: Write the failing check**

Create `test/checks-tools.sh`:

```bash
APP="${APP_DIR:-$HOME/App}"
assert_cmd        "cmake reports 3.30.1"  bash -c 'cmake --version | grep -q 3.30.1'
assert_cmd        "go reports 1.23.3"     bash -c 'go version | grep -q go1.23.3'
assert_path_under "cmake under APP_DIR"   cmake "$APP"
assert_path_under "go under APP_DIR"      go    "$APP"
assert_cmd        "no Bin prefix"         test ! -d "$HOME/Bin"
```

- [ ] **Step 2: Run it to confirm failure**

Run: `test/run.sh tools`
Expected: FAIL - neither tool installed.

- [ ] **Step 3: Add the tools task**

The `[tools]` entries already exist from Task 2. Append the task that installs them:

```toml
[tasks.tools]
depends = ["packages"]
run = "mise install"
```

Go was previously unmanaged: the shell template injected `$HOME/App/go/go1.23.3/bin` into `PATH` while nothing ever installed it (GO-A-1). This task is what makes that path real, and Task 8 removes the hardcoded fragment.

- [ ] **Step 4: Run the check**

Run: `test/run.sh tools`
Expected: PASS on all five assertions.

- [ ] **Step 5: Commit**

```bash
git add mise.toml test/checks-tools.sh
git commit -m "feat: install pinned cmake and go into the application directory"
```

---

### Task 6: Fetch vendored runtime content

**Files:**
- Modify: `mise.toml`
- Create: `test/checks-fetch.sh`

**Interfaces:**
- Consumes: pins `OHMYZSH_REF`, `AUTOSUGGEST_REF`, `CMLIB_*_REF` from Task 2.
- Produces: `vendor/ohmyzsh`, `vendor/zsh-autosuggestions`, `vendor/cmakelib{,-component-*}`, consumed by Tasks 8 and 9.

- [ ] **Step 1: Write the failing check**

Create `test/checks-fetch.sh`:

```bash
assert_cmd "ohmyzsh is a git work tree"  git -C vendor/ohmyzsh rev-parse --is-inside-work-tree
assert_cmd "ohmyzsh at pinned ref"       bash -c '[[ $(git -C vendor/ohmyzsh rev-parse HEAD) == "$OHMYZSH_REF" ]]'
assert_cmd "ohmyzsh not group-writable"  bash -c '[[ ! -w vendor/ohmyzsh || $(stat -c %A vendor/ohmyzsh | cut -c6) == "-" ]]'
assert_cmd "autosuggestions at pin"      bash -c '[[ $(git -C vendor/zsh-autosuggestions rev-parse HEAD) == "$AUTOSUGGEST_REF" ]]'
for c in cmakelib cmakelib-component-cmconf cmakelib-component-cmdef \
         cmakelib-component-cmutil cmakelib-component-storage; do
    assert_cmd "present: $c" test -d "vendor/$c"
done
assert_cmd "no ssh remotes anywhere"     bash -c '! grep -rq "git@github.com" vendor/*/.git/config'
```

The cmakelib check covers all five components, including `cmakelib-component-cmconf`, which is the currently orphaned gitlink (CMLIB-A-1).

- [ ] **Step 2: Run it to confirm failure**

Run: `test/run.sh fetch`
Expected: FAIL - `vendor/` does not exist.

- [ ] **Step 3: Add the fetch task**

Append to `mise.toml`. All URLs are anonymous HTTPS (GEN-A-4), replacing the four SSH URLs that make a fresh clone impossible today (CMLIB-A-2):

```toml
[tasks.fetch]
run = """
set -euo pipefail
umask g-w,o-w   # ohmyzsh requires this or compinit fails (ZSH-A-2)
mkdir -p vendor

fetch_pinned() {
    local name="$1" url="$2" ref="$3" dir="vendor/$1"
    if [[ ! -d $dir/.git ]]; then
        rm -rf "$dir"
        git clone --quiet "$url" "$dir"
    fi
    git -C "$dir" fetch --quiet --tags origin
    git -C "$dir" checkout --quiet --force "$ref"
}

fetch_pinned ohmyzsh             https://github.com/ohmyzsh/ohmyzsh.git                       "$OHMYZSH_REF"
fetch_pinned zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git         "$AUTOSUGGEST_REF"
fetch_pinned cmakelib            https://github.com/cmakelib/cmakelib.git                     "$CMLIB_REF"
fetch_pinned cmakelib-component-cmconf  https://github.com/cmakelib/cmakelib-component-cmconf.git  "$CMLIB_CMCONF_REF"
fetch_pinned cmakelib-component-cmdef   https://github.com/cmakelib/cmakelib-component-cmdef.git   "$CMLIB_CMDEF_REF"
fetch_pinned cmakelib-component-cmutil  https://github.com/cmakelib/cmakelib-component-cmutil.git  "$CMLIB_CMUTIL_REF"
fetch_pinned cmakelib-component-storage https://github.com/cmakelib/cmakelib-component-storage.git "$CMLIB_STORAGE_REF"
"""
```

ohmyzsh must be a clone, not an archive: its update check aborts unless `$ZSH` is a git work tree (ZSH-A-1).

- [ ] **Step 4: Run the check**

Run: `test/run.sh fetch`
Expected: PASS on all nine assertions.

- [ ] **Step 5: Commit**

```bash
git add mise.toml test/checks-fetch.sh
git commit -m "feat: fetch vendored runtime content over https at pinned refs"
```

---

### Task 7: Build Neovim from source

**Files:**
- Modify: `mise.toml`
- Create: `test/checks-nvim.sh`

**Interfaces:**
- Consumes: `cmake` from Task 5, `packages` from Task 3.
- Produces: `nvim` binary under `$APP_DIR/bin`.

- [ ] **Step 1: Write the failing check**

Create `test/checks-nvim.sh`:

```bash
APP="${APP_DIR:-$HOME/App}"
assert_cmd        "nvim reports v0.11.6"   bash -c 'nvim --version | head -1 | grep -q "v0.11.6"'
assert_cmd        "no dev suffix"          bash -c '! nvim --version | head -1 | grep -q dev'
assert_cmd        "built RelWithDebInfo"   bash -c 'nvim --version | grep -q RelWithDebInfo'
assert_path_under "nvim under APP_DIR"     nvim "$APP"
```

The "no dev suffix" check is the one that matters: it proves the tarball build produced correct version stamping (NVIM-A-4), which is the risk this approach carries.

- [ ] **Step 2: Run it to confirm failure**

Run: `test/run.sh nvim`
Expected: FAIL - nvim not installed.

- [ ] **Step 3: Add the build task**

Append to `mise.toml`. Freshness keys on the version stamp, not the source tree (spec 5.5) - one source, one output:

```toml
[tasks.nvim]
depends = ["tools", "packages"]
sources = [".build/nvim.version"]
outputs = ["{{env.APP_DIR}}/bin/nvim"]
run = """
set -euo pipefail
mkdir -p .build
# The stamp carries the prefix as well as the version: changing APP_DIR must
# retrigger the build, and upstream requires a clean build dir whenever
# CMAKE_INSTALL_PREFIX changes.
printf '%s\n%s\n' "$NVIM_VERSION" "$APP_DIR" > .build/nvim.version
src=".build/neovim-${NVIM_VERSION}"
if [[ ! -d $src ]]; then
    curl -fsSL "https://github.com/neovim/neovim/archive/refs/tags/${NVIM_VERSION}.tar.gz" \
      | tar -xz -C .build
    mv ".build/neovim-${NVIM_VERSION#v}" "$src"
fi
cd "$src"
make CMAKE_BUILD_TYPE=RelWithDebInfo \
     CMAKE_INSTALL_PREFIX="$APP_DIR" \
     CMAKE_PRG="$(command -v cmake)"
make CMAKE_INSTALL_PREFIX="$APP_DIR" install
"""
```

The variable is `CMAKE_PRG`, not `CMAKE_PROGRAM`. Neovim's Makefile declares
`CMAKE_PRG ?= $(shell (command -v cmake3 || echo cmake))`; any other spelling is
silently ignored and make falls back to a bare `cmake` on `PATH` - which is
exactly the failure NVIM-R-5 exists to prevent, and it would not error, it would
just quietly use the wrong cmake. On a first run `$APP_DIR/bin` is not yet on
`PATH`, and the current implementation only works because a system cmake happens
to exist.

- [ ] **Step 4: Run the check**

Run: `test/run.sh nvim`
Expected: PASS on all four. This is the slowest task - the container build takes several minutes.

- [ ] **Step 5: Commit**

```bash
git add mise.toml test/checks-nvim.sh
git commit -m "feat: build neovim v0.11.6 RelWithDebInfo from pinned tarball"
```

---

### Task 8: Render templates and extract the theme

**Files:**
- Modify: `mise.toml`
- Modify: `zsh/template/zshrc_template`
- Create: `zsh/custom/themes/muse.zsh-theme`
- Create: `test/checks-render.sh`

**Interfaces:**
- Consumes: `vendor/` from Task 6.
- Produces: `zsh/zshrc`, `vim/init.vim` - the link targets for Task 9. `zsh/config` is **not** produced; see Step 4a.

- [ ] **Step 1: Write the failing check**

Create `test/checks-render.sh`:

```bash
assert_cmd    "zshrc rendered"          test -f zsh/zshrc
assert_cmd    "init.vim rendered"       test -f vim/init.vim
assert_cmd    "no unsubstituted tokens" bash -c '! grep -rq "___[A-Z_]*___" zsh/zshrc vim/init.vim'
assert_cmd    "config_template gone"    test ! -f zsh/template/config_template
assert_cmd    "no zsh-emitted CMLIB"    bash -c '! grep -rq CMLIB zsh/template/'
assert_absent "GO_BIN_DIR gone"         "GO_BIN_DIR"  zsh/template/zshrc_template
assert_absent "USER_BIN_DIR gone"       "USER_BIN_DIR" zsh/template/zshrc_template
assert_absent "ghcup line gone"         "ghcup"        zsh/template/zshrc_template
assert_absent "no hardcoded username"   "/home/h"      zsh/template/zshrc_template
assert_cmd    "theme committed"         test -f zsh/custom/themes/muse.zsh-theme
assert_cmd    "patch file gone"         test ! -f zsh/muse_theme.patch
```

- [ ] **Step 2: Run it to confirm failure**

Run: `test/run.sh render`
Expected: FAIL - nothing rendered, template still carries the removed fragments.

- [ ] **Step 3: Extract the theme**

Copy the upstream theme and apply the single change the patch makes, then delete the patch:

```bash
cp vendor/ohmyzsh/themes/muse.zsh-theme zsh/custom/themes/muse.zsh-theme
```

Then edit `zsh/custom/themes/muse.zsh-theme`: in the `PROMPT=` assignment on line 1, insert a literal newline immediately before the closing prompt glyph sequence, so the prompt renders on two lines. This is the entirety of what `zsh/muse_theme.patch` did. Then:

```bash
git rm zsh/muse_theme.patch
```

Patching a freshly fetched tree is not idempotent and breaks whenever upstream moves (ZSH-R-4); a committed theme file in the already-configured custom directory replaces it.

- [ ] **Step 4a: Delete the shell configuration fragment**

`zsh/template/config_template` contains nothing but the two cmakelib exports and
a no-op `export PATH="${PATH}"`. Those exports are now declared in `mise.toml`
`[env]` (Task 2) and reach the shell through `mise activate`, so the whole file,
its rendered output `zsh/config`, and the `~/.zshrc_config` symlink all
disappear.

```bash
git rm zsh/template/config_template
```

This is the fix for the repository's clearest structural defect: cmakelib's own
setup step is a no-op while its environment is emitted from the shell's
template, with the coupling recorded only in a source comment (CMLIB-A-3).
Declaring the values where the tool owns them satisfies GEN-R-9, ZSH-R-9 and
CMLIB-R-3 at once.

- [ ] **Step 4: Edit the shell template**

In `zsh/template/zshrc_template`:

1. Delete the line `PATH="___USER_BIN_DIR___:___GO_BIN_DIR___:${PATH}"` and replace it with `eval "$(mise activate zsh)"`. Tool visibility now comes from mise activation, covering every installed artifact at once (ZSH-R-10, GO-R-2).
2. Delete the final ghcup line entirely. It is dead - the directory does not exist, no Haskell toolchain is present, and it hardcodes a username (GO-A-4, GEN-R-2).
3. Change `ZSH_PROJECT_DIR=___OHMYZSH_PROJECT_DIR___` so `ZSH` points at `vendor/ohmyzsh` and `ZSH_CUSTOM` points at the repository's `zsh/custom`.

- [ ] **Step 5: Add the render task**

```toml
[tasks.render]
depends = ["fetch"]
sources = ["zsh/template/*", "vim/template/*", "mise.toml"]
outputs = ["zsh/zshrc", "vim/init.vim"]
run = """
set -euo pipefail
root="$(git rev-parse --show-toplevel)"

cp zsh/template/zshrc_template    zsh/zshrc
cp vim/template/init_template.vim vim/init.vim

sed -i "s|___OHMYZSH_PROJECT_DIR___|${root}/vendor|g" zsh/zshrc
sed -i "s|___VIM_BASE_DIR___|${root}/vim|g"           vim/init.vim
"""
```

Two placeholders are ported. `___USER_BIN_DIR___` and `___GO_BIN_DIR___` are
deleted (spec 7), and `___CMAKELIB_DIR___` disappears together with its template
in Step 4a.

- [ ] **Step 6: Run the check**

Run: `test/run.sh render`
Expected: PASS on all ten assertions.

- [ ] **Step 7: Commit**

```bash
git add mise.toml zsh/template/zshrc_template zsh/custom/themes/muse.zsh-theme test/checks-render.sh
git rm --cached zsh/muse_theme.patch zsh/template/config_template 2>/dev/null || true
git commit -m "feat: render configs, commit theme, move cmakelib env to the tool layer"
```

---

### Task 9: Deploy symlinks idempotently

**Files:**
- Modify: `mise.toml`
- Create: `test/checks-link.sh`

**Interfaces:**
- Consumes: rendered files from Task 8.
- Produces: the four symlinks in `$HOME`.

- [ ] **Step 1: Write the failing check**

Create `test/checks-link.sh`:

```bash
for target in "$HOME/.zshrc" \
              "$HOME/.config/nvim/init.vim" "$HOME/.config/kitty/kitty.conf"; do
    assert_cmd "is a symlink: $target"  test -L "$target"
    assert_cmd "resolves: $target"      test -e "$target"
done
assert_cmd "kitty parent dir created"   test -d "$HOME/.config/kitty"
assert_cmd "no stale zshrc_config link" test ! -e "$HOME/.zshrc_config"
```

The harness already runs `./setup` twice, so a PASS here also proves idempotence - which is precisely what `kitty/setup.sh` fails today, because it links without replacing and never creates the parent directory (KITTY-A-1).

- [ ] **Step 2: Run it to confirm failure**

Run: `test/run.sh link`
Expected: FAIL - no links exist.

- [ ] **Step 3: Add the link task**

```toml
[tasks.link]
depends = ["render"]
run = """
set -euo pipefail
root="$(git rev-parse --show-toplevel)"

link() {
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2"
}

link "${root}/zsh/zshrc"        "$HOME/.zshrc"
link "${root}/vim/init.vim"     "$HOME/.config/nvim/init.vim"
link "${root}/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
"""
```

`mkdir -p` then `ln -sfn` makes every deployment repeatable without a preceding removal.

- [ ] **Step 4: Run the check**

Run: `test/run.sh link`
Expected: PASS on all eight assertions.

- [ ] **Step 5: Commit**

```bash
git add mise.toml test/checks-link.sh
git commit -m "feat: deploy configuration symlinks idempotently"
```

---

### Task 10: Remove the legacy implementation

Only after Task 9 passes. This is the destructive task and is deliberately last and separate, so it reverts cleanly.

**Files:**
- Delete: `setup.sh`, `lib.sh`
- Delete: `cmake/setup.sh`, `cmake/install_deps.sh`, `cmakelib/setup.sh`, `cmakelib/install_deps.sh`, `flatpak/setup.sh`, `flatpak/install_deps.sh`, `kitty/setup.sh`, `kitty/install_deps.sh`, `vim/setup.sh`, `vim/install_deps.sh`, `zsh/setup.sh`, `zsh/install_deps.sh`
- Delete: `.gitmodules`
- Create: `test/checks-acceptance.sh`

- [ ] **Step 1: Write the acceptance check**

Create `test/checks-acceptance.sh`, covering the spec's section 10 criteria not already covered task-by-task:

```bash
assert_cmd "no submodules"           bash -c '[[ -z $(git ls-files -s | awk "\$1==160000") ]]'
assert_cmd "no .gitmodules"          test ! -f .gitmodules
assert_cmd "no legacy scripts"       bash -c '[[ -z $(git ls-files "*/setup.sh" "*/install_deps.sh" lib.sh setup.sh) ]]'
assert_cmd "no OS conditionals"      bash -c '! grep -rqi "OS_NAME\|if debian\|apt install" --include="*.toml" --include="setup" .'
assert_cmd "no hardcoded username"   bash -c '! grep -rq "/home/h" --include="*_template" --include="*.toml" .'
assert_cmd "no ssh urls"             bash -c '! grep -rq "git@github.com" --include="*.toml" .'
assert_cmd "every tool has a doc"    bash -c 'for t in zsh neovim cmake cmakelib go kitty desktop-apps; do test -f "docs/requirements/tool-$t.md" || exit 1; done'
```

- [ ] **Step 2: Run it to confirm failure**

Run: `test/run.sh acceptance`
Expected: FAIL - submodules and scripts still present.

- [ ] **Step 3: Remove the submodules**

```bash
git rm -r --cached cmake/CMake vim/neovim zsh/ohmyzsh \
    zsh/custom/plugins/zsh-autosuggestions \
    cmakelib/cmakelib cmakelib/cmakelib-component-cmconf \
    cmakelib/cmakelib-component-cmdef cmakelib/cmakelib-component-cmutil \
    cmakelib/cmakelib-component-storage
git rm .gitmodules
rm -rf .git/modules/cmake .git/modules/vim .git/modules/zsh .git/modules/cmakelib
rm -rf cmake/CMake vim/neovim zsh/ohmyzsh zsh/custom/plugins/zsh-autosuggestions
rm -rf cmakelib/cmakelib cmakelib/cmakelib-component-cmconf \
       cmakelib/cmakelib-component-cmdef cmakelib/cmakelib-component-cmutil \
       cmakelib/cmakelib-component-storage
```

Nine gitlinks are removed, one more than `.gitmodules` declares - `cmakelib-component-cmconf` is the orphan (CMLIB-A-1).

- [ ] **Step 4: Remove the legacy scripts**

```bash
git rm setup.sh lib.sh \
    cmake/setup.sh cmake/install_deps.sh \
    cmakelib/setup.sh cmakelib/install_deps.sh \
    flatpak/setup.sh flatpak/install_deps.sh \
    kitty/setup.sh kitty/install_deps.sh \
    vim/setup.sh vim/install_deps.sh \
    zsh/setup.sh zsh/install_deps.sh
```

- [ ] **Step 5: Run the full acceptance check**

Run: `test/run.sh acceptance`
Expected: PASS on all seven, and every earlier task's checks still pass.

- [ ] **Step 6: Update the README**

Modify `README.md`: replace the "Build and Install" section, which documents `./setup.sh <tool_name>` and `$HOME/Bin`, with the single command `./setup` and a note that the install prefix is `$APP_DIR` (default `~/App`). Point at `docs/adding-a-new-tool.md` for additions.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: remove 14 legacy shell scripts and 9 git submodules"
```

---

## Verification against the spec

Spec section 10 acceptance criteria, mapped to the task that proves each:

| Criterion | Proven by |
|---|---|
| 1. Fresh clone + `./setup` with no SSH key | Task 6 (https-only), Task 10 acceptance |
| 2. Second run is a no-op | Harness runs `./setup` twice on every task |
| 3. `git submodule status` reports nothing | Task 10 |
| 4. Nothing outside repo and `$APP_DIR` but links | Tasks 5, 9 |
| 5. Every pin in `mise.toml` | Task 2 |
| 6. `nvim v0.11.6` RelWithDebInfo | Task 7 |
| 7. `omz update` works | Task 6 (git work tree assertion) |
| 8. zsh login shell, no manual `chsh` | Task 3 |
| 9. Every `PATH` entry exists, `go version` works | Tasks 5, 8 |
| 10. No hardcoded username | Tasks 8, 10 |
| 11. 17 apps install with third-party repos disabled | Task 4 |
| 12. Package names resolve | Task 3 |
| 13. Build succeeds with no pre-installed tooling | Task 7 (container installs none) |
| 14. No OS conditionals | Task 10 |
| 15. Every tool has a document, zero dangling citations | Task 10 |

## Known gaps in the harness

Recorded so the executor does not mistake a green run for total coverage:

- The container cannot launch graphical applications. Task 4 proves the remote is unfiltered and every application ID resolves, not that the apps run.
- `chsh` inside a container is not identical to a real login. Task 3 checks the passwd entry, not an interactive login.
- Kitty cannot run headless. Task 9 checks the link and its parent directory only.
- A first real run on the actual notebook remains necessary after Task 10.
