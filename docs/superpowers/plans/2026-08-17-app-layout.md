# Application-Directory Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every managed tool one directory named after it under the application directory, and make every pinned tool resolve by name from anywhere on the machine.

**Architecture:** Two process-start environment variables do the work. `MISE_GLOBAL_CONFIG_FILE` points the orchestrator's global configuration at this repository's `mise.toml`, which extends tool resolution beyond the repository without duplicating a pin. `MISE_INSTALLS_DIR` moves orchestrator-managed installs from the data directory into the application root. Neovim's CMake prefix and the fetch destinations are changed directly. Both variables are read before the configuration is parsed, so both are exported by the entry point and the rendered login profile, never from `[env]`.

**Tech Stack:** mise 2026.8.6 (TOML tasks, Tera templating), Bash, Zsh, podman-based check harness.

**Spec:** `docs/superpowers/specs/2026-08-17-app-layout-design.md`

## Global Constraints

- **Pins live in exactly one file** (GEN-R-7): `mise.toml`. Never restate a version anywhere else.
- **`{{config_root}}` is prohibited in `mise.toml`** once Task 3 lands: the file is also loaded as the global configuration, where the config root defaults to `$HOME` (spec F-8).
- **Never set `MISE_INSTALLS_DIR` or `MISE_GLOBAL_CONFIG_FILE` in `[env]`** — both are read at process start; setting them there makes installs and lookups disagree (spec F-6a).
- **The harness clones from HEAD.** Commit before every `test/run.sh` invocation or you test stale state.
- **Harness signature:** `test/run.sh <check> <target> <privileged|unprivileged> [expect-fail]`.
- **mise renders task `run` bodies through Tera.** `{#`, `{{`, `{%` are metacharacters; `${#arr[@]}` will not parse inside a task body.
- **Rendered outputs are guarded.** `zsh/zshrc` and `vim/init.vim` are gitignored; `[tasks.render]` refuses to overwrite either when its content differs from a fresh render. After changing a template, move the old file aside — do not edit the rendered file.
- **Requirement identifiers are stable.** Superseding text is appended; original text is never deleted or rewritten (the APPS-A-9 precedent).
- **No status/progress output** in scripts or tasks unless required for correctness.
- **ASCII only** in all files touched.

## File Structure

| File | Responsibility | Tasks |
|---|---|---|
| `mise.toml` | Pins, `[env]`, all tasks | 1, 3, 6, 7, 8 |
| `setup` | Process-start environment, orchestrator bootstrap | 4, 5, 6 |
| `zsh/template/zshrc_template` | Login-shell environment, activation | 3, 4, 5, 6 |
| `test/run.sh` | Container harness environment and PATH | 4, 5, 6 |
| `test/checks-*.sh` | Observable checks | 2, 3, 4, 5, 6, 7, 8, 9 |
| `.gitignore` | `_vendor/` entry | 7 |
| `docs/requirements/general.md` | Definitions, global assumptions and requirements | 2, 3, 4, 5, 7, 8 |
| `docs/requirements/tool-*.md` | Per-tool requirements | 3, 4, 6, 7 |
| `docs/spec-mise-migration.md` | Superseded claims | 3 |
| `README.md` | `_vendor/` migration notes | 7 |

---

### Task 1: Commit the pending Go pin bump

The working tree carries an uncommitted bump of the Go pin from 1.23.3 to 1.26.6. Because the harness clones from HEAD, nothing later in this plan can be verified until it is committed.

**Files:**
- Modify: none — the edits already exist in the working tree
- Verify: `mise.toml:44`, `test/checks-tools.sh:3`, `docs/requirements/tool-go.md`, `docs/spec-mise-migration.md`

- [ ] **Step 1: Confirm the working tree holds exactly the expected change**

```bash
git diff --stat
```

Expected: four files — `docs/requirements/tool-go.md`, `docs/spec-mise-migration.md`, `mise.toml`, `test/checks-tools.sh`. If `zsh/template/zshrc_template` or `docs/requirements/tool-zsh.md` appear, an earlier shims experiment was not reverted; run `git checkout -- zsh/template/zshrc_template docs/requirements/tool-zsh.md` first.

- [ ] **Step 2: Confirm no stale version literal remains in live files**

```bash
grep -rn "1\.23\.3" mise.toml test/ docs/requirements/
```

Expected: no output. Two matches in `docs/spec-mise-migration.md:86,447` are historical descriptions of the pre-migration hardcoded path and MUST remain.

- [ ] **Step 3: Commit**

```bash
git add mise.toml test/checks-tools.sh docs/requirements/tool-go.md docs/spec-mise-migration.md
git commit -m "chore: bump the Go pin to 1.26.6

1.26.6 is the current stable release (2026-08-13); 1.27 exists only as a
release candidate. GO-R-1's check no longer restates the literal, which is
what went stale in three places at the previous bump.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Verify the harness passes on the committed state**

Run: `test/run.sh tools tools unprivileged`
Expected: PASS, including `go reports 1.26.6`.

---

### Task 2: Pin registry section

**Files:**
- Modify: `docs/requirements/general.md` (append to §1; new subsection in §4; two rows in §5)
- Modify: `docs/requirements/tool-go.md:36` (pin table row)
- Create: `test/checks-docs.sh`
- Modify: `test/run.sh` is not touched; the new check file is selected by name

**Interfaces:**
- Produces: `GEN-D-16` (pin registry), `GEN-R-20` (index rule). Later tasks cite both.

- [ ] **Step 1: Write the failing check**

Create `test/checks-docs.sh`:

```bash
# GEN-R-20: the requirements set indexes pins, it never restates their values.
# Every value in the pin file is searched for across docs/requirements/; a hit
# means a second copy exists and will go stale, which is what happened to the
# Go pin at 1.23.3.
assert_cmd "no requirements doc restates a pinned value" bash -c '
    fail=0
    while IFS= read -r value; do
        [ -z "$value" ] && continue
        if grep -rqF "$value" docs/requirements/; then
            echo "restated pin value: $value" >&2
            fail=1
        fi
    done <<< "$(sed -n "s/^[A-Za-z_]* *= *\"\([^\"]*\)\".*/\1/p" mise.toml \
                | grep -E "^(v?[0-9]+\.[0-9]+|[0-9a-f]{40})")"
    [ "$fail" -eq 0 ]
'
assert_cmd "every registry key resolves in the pin file" bash -c '
    fail=0
    for key in min_version cmake go NVIM_VERSION OHMYZSH_REF AUTOSUGGEST_REF \
               CMLIB_REF CMLIB_CMCONF_REF CMLIB_CMDEF_REF CMLIB_CMUTIL_REF \
               CMLIB_STORAGE_REF; do
        grep -qE "^ *$key *=" mise.toml || { echo "missing key: $key" >&2; fail=1; }
    done
    [ "$fail" -eq 0 ]
'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `test/run.sh docs render unprivileged`
Expected: FAIL on `no requirements doc restates a pinned value`, naming `1.26.6` — `docs/requirements/tool-go.md:36` still carries it.

- [ ] **Step 3: Add the definition to `general.md` §1**

Append after `GEN-D-15`:

```markdown
**GEN-D-16 Pin registry.** The single file in which every pin (GEN-D-5) is
recorded: `mise.toml`. It holds pins under three mechanisms - the
orchestrator's own `min_version`, the `[tools]` table for dev tools
(GEN-D-9), and `[env]` variables for build inputs (GEN-D-6) and runtime
content (GEN-D-7).
```

- [ ] **Step 4: Add the registry subsection to `general.md` §4**

Insert after the `Correctness` subsection, before `Verifiability`:

```markdown
### Pins

**GEN-R-20** Every pinned source SHALL appear in the registry table below,
identified by the key under which the pin registry (GEN-D-16) records it. The
table SHALL NOT restate the pinned value: it is an index into the registry,
not a second copy of it, and GEN-R-7 continues to hold unchanged. A per-tool
document MAY describe what its pin means but SHALL NOT reproduce the value.

| Source | Classification | Mechanism | Key |
|---|---|---|---|
| mise | orchestrator | top-level | `min_version` |
| cmake | dev tool | `[tools]` | `cmake` |
| go | dev tool | `[tools]` | `go` |
| neovim | build input | `[env]` | `NVIM_VERSION` |
| oh-my-zsh | runtime content | `[env]` | `OHMYZSH_REF` |
| zsh-autosuggestions | runtime content | `[env]` | `AUTOSUGGEST_REF` |
| cmakelib | runtime content | `[env]` | `CMLIB_REF` |
| cmakelib-component-cmconf | runtime content | `[env]` | `CMLIB_CMCONF_REF` |
| cmakelib-component-cmdef | runtime content | `[env]` | `CMLIB_CMDEF_REF` |
| cmakelib-component-cmutil | runtime content | `[env]` | `CMLIB_CMUTIL_REF` |
| cmakelib-component-storage | runtime content | `[env]` | `CMLIB_STORAGE_REF` |
```

- [ ] **Step 5: Add the verification rows to `general.md` §5**

```markdown
| GEN-D-16 | Every key named in the registry table resolves in the pin file |
| GEN-R-20 | Searching the requirements directory for any value recorded in the pin file returns nothing |
```

- [ ] **Step 6: Remove the restated value from `tool-go.md`**

Replace the pin-table row at `docs/requirements/tool-go.md:36`:

```markdown
| Version | recorded in the pin registry (GEN-D-16) under key `go` |
```

- [ ] **Step 7: Run the check to verify it passes**

Run: `test/run.sh docs render unprivileged`
Expected: PASS, both assertions.

- [ ] **Step 8: Commit**

```bash
git add docs/requirements/general.md docs/requirements/tool-go.md test/checks-docs.sh
git commit -m "docs: index pins in one place instead of restating them

GEN-D-16 names the pin registry; GEN-R-20 makes the requirements set an
index into it. checks-docs.sh fails if any requirements document restates
a value the pin file records - the drift that put a stale 1.23.3 in three
places.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Global tool visibility

**Files:**
- Modify: `zsh/template/zshrc_template:146-152`
- Modify: `mise.toml` `[tasks.render]` (the `sed` placeholder list)
- Modify: `docs/requirements/tool-zsh.md` (ZSH-R-8, ZSH-R-13, ZSH-R-14, new ZSH-R-15, verification rows)
- Modify: `docs/requirements/tool-go.md` (GO-R-2 and its verification row)
- Modify: `docs/requirements/general.md` (GEN-A-6 supersession)
- Modify: `docs/spec-mise-migration.md` §5 (supersession)
- Modify: `test/checks-render.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: render placeholder `___MISE_CONFIG_FILE___`; requirement `ZSH-R-15`. Task 4 adds a second export beside it and updates the same ZSH-R-13 count.

- [ ] **Step 1: Write the failing check**

Append to `test/checks-render.sh`:

```bash
assert_cmd "global config file exported before activation" bash -c '
    grep -q "^export MISE_GLOBAL_CONFIG_FILE=" zsh/zshrc &&
    [ "$(grep -n "^export MISE_GLOBAL_CONFIG_FILE=" zsh/zshrc | cut -d: -f1)" \
      -lt "$(grep -n "mise activate zsh" zsh/zshrc | cut -d: -f1)" ]
'
assert_cmd "global config file points at the pin registry" bash -c '
    grep -q "^export MISE_GLOBAL_CONFIG_FILE=\"$PWD/mise.toml\"" zsh/zshrc
'
assert_cmd "no unsubstituted placeholder" bash -c '! grep -q "___" zsh/zshrc'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `test/run.sh render render unprivileged`
Expected: FAIL on `global config file exported before activation`.

- [ ] **Step 3: Add the placeholder to the render task**

In `mise.toml` `[tasks.render]`, add a fourth `-e` expression to the `sed` invocation:

```bash
    sed -e "s|___OHMYZSH_PROJECT_DIR___|${root}/_vendor|g" \
        -e "s|___ZSH_CUSTOM_DIR___|${root}/zsh/custom|g" \
        -e "s|___VIM_BASE_DIR___|${root}/vim|g" \
        -e "s|___MISE_CONFIG_FILE___|${root}/mise.toml|g" \
        "$template" > "$new"
```

- [ ] **Step 4: Add the export to the template**

In `zsh/template/zshrc_template`, insert between the `PATH` export and the activation guard:

```sh
# Activation resolves tools by walking up from $PWD, so on its own it exposes
# them only beneath this repository - narrower than the unconditional path
# fragments it replaced (ZSH-R-10, ZSH-R-11). Naming this repository's
# configuration as the global one restores machine-wide resolution without a
# second pin: it is the same file, reached by a second route. Read before the
# configuration is parsed, so it cannot come from [env].
export MISE_GLOBAL_CONFIG_FILE="___MISE_CONFIG_FILE___"
```

- [ ] **Step 5: Re-render and confirm the diff is only the new export**

```bash
mv zsh/zshrc /tmp/zshrc.before
./setup render
diff -u /tmp/zshrc.before zsh/zshrc
```

Expected: one added comment block and one added `export` line, nothing else.

- [ ] **Step 6: Verify resolution from outside the repository**

```bash
cd "$HOME" && zsh -i -c 'command -v go; go version; cmake --version | head -1'
```

Expected: `go` resolves under the application directory and reports the pinned version; `cmake` reports the pinned version, **not** the system 4.3.0. A system version here means the global configuration is not being read — stop and diagnose before continuing.

- [ ] **Step 7: Verify no double-load inside the repository**

```bash
cd "$(git rev-parse --show-toplevel)" && mise ls
```

Expected: each tool listed exactly once. The repository configuration is now both the local and the global configuration; if any tool is listed twice, remove the export from `setup` (it is only required for interactive shells, which resolve nothing locally) and re-check.

- [ ] **Step 8: Supersede GEN-A-6**

In `docs/requirements/general.md`, append to `GEN-A-6` **without altering its existing text**:

```markdown
`SUPERSEDED IN PART 2026-08-17`: the closing clause ("no machine-global
configuration participates") no longer holds. Upward resolution is unchanged
and still correct; what changed is that this repository now names its own
configuration file as the global one (ZSH-R-15), deliberately, so that pinned
tools resolve outside the repository. No pin is duplicated by this - the
global configuration is the pin registry (GEN-D-16), reached by a second
route.
```

- [ ] **Step 9: Apply the same supersession to the migration spec**

In `docs/spec-mise-migration.md` §5, append after the sentence ending "so no global config is involved":

```markdown
Superseded 2026-08-17: a global configuration is now involved, and it is this
same file. See GEN-A-6 and ZSH-R-15.
```

- [ ] **Step 10: Add ZSH-R-15 and update ZSH-R-13, ZSH-R-8, ZSH-R-14**

In `docs/requirements/tool-zsh.md`:

```markdown
**ZSH-R-15** The rendered configuration SHALL name this repository's
configuration file as the orchestrator's global configuration. Activation
alone is insufficient: it resolves tools by walking upward from the working
directory (GEN-A-6), so it exposes them only beneath this repository, while
the fragments it replaced (ZSH-R-10, ZSH-R-11) were unconditional and
therefore machine-wide. The variable is read before configuration is parsed
and SHALL therefore be exported above the activation line and SHALL NOT be
set from `[env]`.
```

Update `ZSH-R-13` to read "the application directory, the orchestrator's data
directory, the search path and the global configuration file (ZSH-R-15)", and
its verification row to say "the four exports". Update `ZSH-R-8` and
`ZSH-R-14` to name three placeholders rather than two.

Add the verification row:

```markdown
| ZSH-R-15 | An interactive shell started outside this repository resolves every pinned tool by name and reports the pinned version, and resolves `cmake` to the pinned version rather than the system one |
```

- [ ] **Step 11: Update GO-R-2**

In `docs/requirements/tool-go.md`, replace GO-R-2's second sentence and its verification row:

```markdown
Visibility of the Go binaries SHALL come from the orchestrator instead, and
SHALL be machine-wide as the removed fragment was: activation beneath this
repository, and the global configuration (ZSH-R-15) everywhere else.
```

```markdown
| GO-R-2 | Every entry in the resulting search path exists, and Go reports the pinned version from a directory outside this repository |
```

- [ ] **Step 12: Run the checks**

Run: `test/run.sh render render unprivileged`
Expected: PASS.

- [ ] **Step 13: Commit**

```bash
git add mise.toml zsh/template/zshrc_template test/checks-render.sh \
        docs/requirements/general.md docs/requirements/tool-zsh.md \
        docs/requirements/tool-go.md docs/spec-mise-migration.md
git commit -m "feat: resolve pinned tools outside the repository

Activation is directory-scoped, so the migration left go unresolvable and
cmake resolving to the system copy once a shell left the repository. Naming
this repository's config as the global one restores machine-wide resolution
without duplicating a pin.

Shims were rejected: with no config in scope they fall through to the next
PATH match, so cmake silently reported the system 4.3.0.

GEN-A-6 and spec section 5 are superseded in place, not rewritten.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Move orchestrator-managed installs into the application root

**Files:**
- Modify: `setup:6-7`
- Modify: `zsh/template/zshrc_template` (beside the other process-start exports)
- Modify: `test/run.sh:70-71` (the harness re-derives setup's process-start exports)
- Modify: `docs/requirements/general.md` (GEN-R-1a, GEN-R-16)
- Modify: `docs/requirements/tool-zsh.md` (ZSH-R-13 count again)
- Verify unchanged: `docs/requirements/tool-cmake.md` (CMAKE-R-2)
- Modify: `test/checks-tools.sh`

**Interfaces:**
- Consumes: the export block established in Task 3.
- Produces: `App/go/<version>/`, `App/cmake/<version>/`. Tasks 5 and 6 place `App/mise/bin/` and `App/nvim/` beside them.

- [ ] **Step 1: Write the failing check**

Append to `test/checks-tools.sh`:

```bash
assert_cmd "go installs directly under APP_DIR" bash -c '
    [ -d "${APP_DIR}/go" ] && [ ! -d "${APP_DIR}/mise/installs/go" ]
'
assert_cmd "cmake installs directly under APP_DIR" bash -c '
    [ -d "${APP_DIR}/cmake" ] && [ ! -d "${APP_DIR}/mise/installs/cmake" ]
'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `test/run.sh tools tools unprivileged`
Expected: FAIL on both — installs are still under `mise/installs/`.

- [ ] **Step 3: Export the variable from the entry point**

In `setup`, extend the existing export block (lines 4-7):

```bash
# APP_DIR, MISE_DATA_DIR and MISE_INSTALLS_DIR are read by mise at process
# start and cannot be set from mise.toml's [env] (GEN-A-7). Setting the
# installs directory there would let an install use one directory while later
# lookups use another. This wrapper exists to export them.
export APP_DIR="${APP_DIR:-$HOME/App}"
export MISE_DATA_DIR="$APP_DIR/mise"
export MISE_INSTALLS_DIR="$APP_DIR"
```

- [ ] **Step 4: Export the same variable from the rendered profile**

In `zsh/template/zshrc_template`, beside `MISE_DATA_DIR`:

```sh
export MISE_INSTALLS_DIR="$APP_DIR"
```

- [ ] **Step 5: Export the same variable in the harness**

`test/run.sh` re-derives setup's process-start exports for the check shell,
because setup ran as a child process and its exports never reached the parent.
Without this the checks resolve no tools at all. After the `MISE_DATA_DIR`
line (`test/run.sh:71`):

```bash
        export MISE_INSTALLS_DIR=\"\$APP_DIR\"
```

- [ ] **Step 6: Re-render**

```bash
mv zsh/zshrc /tmp/zshrc.before
./setup render
diff -u /tmp/zshrc.before zsh/zshrc
```

Expected: one added `export` line.

- [ ] **Step 7: Install and verify the new location**

```bash
./setup tools
mise which go
mise which cmake
```

Expected: both paths begin `$APP_DIR/go/` and `$APP_DIR/cmake/`, not `$APP_DIR/mise/installs/`.

- [ ] **Step 8: Confirm CMAKE-R-2 still holds without editing it**

```bash
grep -n -A2 "CMAKE-R-2" docs/requirements/tool-cmake.md
```

CMAKE-R-2 says the binary is "installed under the application directory",
which stays true at `App/cmake/<version>/`. Expected: no edit needed. If the
text names a path literally rather than the application directory, repoint it.

- [ ] **Step 9: Update GEN-R-1a and GEN-R-16**

In `docs/requirements/general.md`, append to GEN-R-1a:

```markdown
Installed artifacts SHALL be grouped one directory per tool, named after the
tool, directly beneath the application directory. The prohibition on a second
install prefix is unchanged: there remains exactly one prefix, and the
per-tool directories are its contents, not rival prefixes.
```

Update GEN-R-16 to name three process-start variables (the application
directory setting, the data directory, and the installs directory) exported by
the same two places, and update its verification row correspondingly.

- [ ] **Step 10: Update ZSH-R-13**

Raise the export count to five and name the installs directory in the ordered
list, in both the requirement and its verification row.

- [ ] **Step 11: Run the checks**

Run: `test/run.sh tools tools unprivileged`
Expected: PASS.

- [ ] **Step 12: Commit**

```bash
git add setup zsh/template/zshrc_template test/run.sh test/checks-tools.sh \
        docs/requirements/general.md docs/requirements/tool-zsh.md
git commit -m "feat: install orchestrator-managed tools one directory per tool

MISE_INSTALLS_DIR is global rather than per-tool, so go and cmake move
together. Both land directly under the application directory, leaving the
data directory to cache and state.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Move the Neovim install prefix

Neovim currently installs with the application directory as its CMake prefix, scattering `bin/`, `lib64/` and `share/` into the application root.

**Files:**
- Modify: `mise.toml` `[tasks.nvim]` (`outputs`, both `make` invocations)
- Modify: `setup:49`, `zsh/template/zshrc_template`, `test/run.sh:72` (search path)
- Modify: `docs/requirements/tool-neovim.md` (NVIM-R-4)
- Modify: `test/checks-nvim.sh`

**Interfaces:**
- Consumes: `App/` per-tool convention from Task 4.
- Produces: `App/nvim/bin/nvim` on the search path.

- [ ] **Step 1: Write the failing check**

Append to `test/checks-nvim.sh`:

```bash
assert_cmd "nvim owns one directory under APP_DIR" bash -c '
    [ -x "${APP_DIR}/nvim/bin/nvim" ]
'
assert_cmd "nvim does not scatter into APP_DIR root" bash -c '
    [ ! -e "${APP_DIR}/lib64" ] && [ ! -e "${APP_DIR}/share/nvim" ]
'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `test/run.sh nvim nvim unprivileged`
Expected: FAIL on both. This target builds Neovim from source and is the slowest in the plan; it also fetches from GitHub, which has rate-limited previous runs with HTTP 429. A 429 is not a code failure — retry.

- [ ] **Step 3: Change the prefix**

In `mise.toml` `[tasks.nvim]`:

```toml
outputs = ["{{env.APP_DIR}}/nvim/bin/nvim"]
```

and in the body, both invocations:

```bash
make CMAKE_BUILD_TYPE=RelWithDebInfo \
     CMAKE_INSTALL_PREFIX="$APP_DIR/nvim" \
     CMAKE_PRG="$(command -v cmake)"
make CMAKE_INSTALL_PREFIX="$APP_DIR/nvim" install
```

- [ ] **Step 4: Put the new location on the search path**

Neovim is the one managed tool the orchestrator does not resolve by name, so its directory joins the search path explicitly. The orchestrator is still in `$APP_DIR/bin` at this point — Task 6 moves it — so that entry stays for now. In `setup`, replace line 49:

```bash
export PATH="$APP_DIR/bin:$APP_DIR/nvim/bin:$PATH"
```

In `zsh/template/zshrc_template`, the corresponding line:

```sh
export PATH="$APP_DIR/bin:$APP_DIR/nvim/bin:$PATH"
```

In `test/run.sh:72`:

```bash
        PATH=\"\$APP_DIR/bin:\$APP_DIR/nvim/bin:\$PATH\"
```

- [ ] **Step 5: Re-render**

```bash
mv zsh/zshrc /tmp/zshrc.before
./setup render
diff -u /tmp/zshrc.before zsh/zshrc
```

Expected: one changed `PATH` line.

- [ ] **Step 6: Update NVIM-R-4**

In `docs/requirements/tool-neovim.md`, replace NVIM-R-4:

```markdown
**NVIM-R-4** The install prefix SHALL be a directory named after the tool
beneath the application directory (GEN-R-1a), not the application directory
itself. Using the root as the prefix writes `bin/`, `lib64/` and `share/`
into it, which is what the one-directory-per-tool rule exists to prevent.
```

And its verification row:

```markdown
| NVIM-R-4 | The binary resolves at `<application directory>/nvim/bin/nvim`, and the application root contains no `lib64` or `share/nvim` |
```

- [ ] **Step 7: Run the checks**

Run: `test/run.sh nvim nvim unprivileged`
Expected: PASS. Retry on HTTP 429.

- [ ] **Step 8: Commit**

```bash
git add mise.toml setup zsh/template/zshrc_template test/run.sh \
        test/checks-nvim.sh docs/requirements/tool-neovim.md
git commit -m "feat: give Neovim its own directory under the application dir

The application root was Neovim's CMake prefix, so it received bin, lib64
and share. It now owns one directory like every other managed tool, and its
bin directory joins the search path explicitly - it is the one tool the
orchestrator does not resolve by name.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Move the orchestrator binary and retire `App/bin/`

Neovim left `App/bin/` in Task 5, so the orchestrator is now its only occupant. It already owns `App/mise/` for its cache and state, so its binary joins it there and `App/bin/` is retired — making the one-directory-per-tool rule exceptionless. This task runs *after* the Neovim move deliberately: retiring the directory while Neovim still lived in it would drop the editor off the search path and fail this task's own check.

**Files:**
- Modify: `setup:27`, `setup:43-49`
- Modify: `zsh/template/zshrc_template` (the `PATH` export)
- Modify: `test/run.sh:72`
- Modify: `docs/requirements/general.md` (GEN-R-1a)
- Modify: `test/checks-bootstrap.sh`

**Interfaces:**
- Consumes: the `App/<tool>/` convention from Task 4, and the `App/nvim/bin` search-path entry added by Task 5.
- Produces: `App/mise/bin/mise` on the search path. These two are the only application-directory entries the search path names; no later task adds another.

**Note:** `App/mise/` currently holds `downloads/`, `installs/`, `migrations/` and `shims/` — no `bin/`, so there is no collision. On a machine set up before this change, `App/bin/mise` still exists and may still be on `PATH`; the bootstrap guard below must therefore test the new path specifically, or setup will decide the orchestrator is already installed and never place it in its new home.

- [ ] **Step 1: Write the failing check**

Append to `test/checks-bootstrap.sh`:

```bash
assert_cmd "the orchestrator lives in its own directory" bash -c '
    [ -x "${APP_DIR}/mise/bin/mise" ]
'
assert_cmd "no bare bin directory under APP_DIR" bash -c '
    [ ! -e "${APP_DIR}/bin" ]
'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `test/run.sh bootstrap packages privileged`
Expected: FAIL on both — the binary is still at `$APP_DIR/bin/mise`.

- [ ] **Step 3: Move the bootstrap target**

In `setup`, replace the install guard and the `PATH` line Task 5 left at line 49:

```bash
# command -v only sees mise if it is already on PATH, which a prior run of
# this same script cannot guarantee for the current process; check the known
# install path too, or every invocation redownloads mise over the network.
# The test names the new path specifically: a machine set up before the
# orchestrator moved still has a binary at the old one, and trusting
# command -v alone would leave it there forever.
if [ ! -x "$APP_DIR/mise/bin/mise" ]; then
    # MISE_INSTALL_PATH must name a file, not a directory; the installer
    # errors out if given a directory.
    curl -fsSL https://mise.run \
      | MISE_VERSION="v${mise_version}" MISE_INSTALL_PATH="$APP_DIR/mise/bin/mise" sh
fi
export PATH="$APP_DIR/mise/bin:$APP_DIR/nvim/bin:$PATH"
```

- [ ] **Step 4: Create the directory before the installer needs it**

The installer writes a file, not a tree. Extend `setup:27`:

```bash
mkdir -p "$APP_DIR" "$MISE_DATA_DIR" "$MISE_DATA_DIR/bin"
```

- [ ] **Step 5: Update the rendered profile**

In `zsh/template/zshrc_template`, replace the `PATH` export set in Task 5:

```sh
export PATH="$APP_DIR/mise/bin:$APP_DIR/nvim/bin:$PATH"
```

- [ ] **Step 6: Update the harness**

In `test/run.sh:72`:

```bash
        PATH=\"\$APP_DIR/mise/bin:\$APP_DIR/nvim/bin:\$PATH\"
```

- [ ] **Step 7: Re-render**

```bash
mv zsh/zshrc /tmp/zshrc.before
./setup render
diff -u /tmp/zshrc.before zsh/zshrc
```

Expected: one changed `PATH` line.

- [ ] **Step 8: Verify the orchestrator bootstraps into its new home**

```bash
./setup render
ls -l "$APP_DIR/mise/bin/mise"
command -v mise
```

Expected: the binary exists at the new path. `command -v mise` may still report the old one in an already-running shell; open a new shell to confirm, and note that `App/bin/mise` is left in place for the user to remove (Task 9).

- [ ] **Step 9: Update GEN-R-1a**

Extend the sentence added in Task 4 so the rule admits no exception:

```markdown
This includes the orchestrator itself, which owns the directory named after
it rather than a shared binary directory. There is no bare binary directory
under the application directory.
```

- [ ] **Step 10: Run the checks**

Run: `test/run.sh bootstrap packages privileged`
Expected: PASS. The `no bare bin directory` assertion is meaningful only in the container, which builds the application directory from empty — nothing creates `App/bin` there once this task lands. On a machine set up before this change the directory persists until the user removes it (Task 9), so expect the local filesystem and the container to disagree until then. That disagreement is the harness working as designed, not a failure.

- [ ] **Step 11: Commit**

```bash
git add setup zsh/template/zshrc_template test/run.sh \
        test/checks-bootstrap.sh docs/requirements/general.md
git commit -m "feat: move the orchestrator binary into its own directory

App/bin held mise and nvim; with nvim leaving it in the next task, keeping
a shared binary directory for one occupant carved out an exception to the
one-directory-per-tool rule and bought nothing. mise already owned App/mise
for its cache and state, so its binary joins it there.

The bootstrap guard now tests the new path specifically: a machine set up
before this change still has a binary at the old one, and command -v alone
would leave it there permanently.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Move fetched runtime content

**Files:**
- Modify: `mise.toml` `[env]` (`CMLIB_DIR`, `CMLIB_COMPONENT_LOCAL_BASE_PATH`), `[tasks.fetch]`, `[tasks.render]`
- Modify: `.gitignore`
- Modify: `README.md:92,98`
- Modify: `docs/requirements/general.md` (GEN-D-7, GEN-D-12, GEN-R-3, GEN-R-17a)
- Modify: `docs/requirements/tool-cmakelib.md`, `docs/requirements/tool-zsh.md` (ZSH-R-12)
- Modify: `test/checks-fetch.sh`

**Interfaces:**
- Consumes: `App/` per-tool convention.
- Produces: `App/cmakelib/{cmakelib,cmakelib-component-*}`, `App/ohmyzsh/`. `_vendor/` no longer exists.

**Note:** `zsh-autosuggestions` does **not** move. Oh My Zsh resolves plugins only under its custom plugin directory (ZSH-A-7, `VERIFIED`), and ZSH-R-12 already records this as a settled correction.

- [ ] **Step 1: Write the failing check**

Replace the `_vendor` paths in `test/checks-fetch.sh` and add:

```bash
assert_cmd "ohmyzsh is a git work tree"  git -C "${APP_DIR}/ohmyzsh" rev-parse --is-inside-work-tree
assert_cmd "cmakelib holds the library and its components" bash -c '
    [ -d "${APP_DIR}/cmakelib/cmakelib" ] &&
    [ -d "${APP_DIR}/cmakelib/cmakelib-component-cmconf" ] &&
    [ -d "${APP_DIR}/cmakelib/cmakelib-component-storage" ]
'
assert_cmd "the vendored directory is gone" bash -c '[ ! -d _vendor ]'
assert_cmd "the fixed-path exception still holds" bash -c '
    [ -d zsh/custom/plugins/zsh-autosuggestions ]
'
assert_cmd "no config_root in the pin file" bash -c '! grep -q "config_root" mise.toml'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `test/run.sh fetch fetch unprivileged`
Expected: FAIL — content is still under `_vendor/`.

- [ ] **Step 3: Repoint the cmakelib exports**

In `mise.toml` `[env]`, replace lines 27-28:

```toml
CMLIB_DIR                       = "{{env.APP_DIR}}/cmakelib/cmakelib"
CMLIB_COMPONENT_LOCAL_BASE_PATH = "{{env.APP_DIR}}/cmakelib/"
```

`{{config_root}}` is deliberately not used: this file is also the global configuration, where the config root defaults to `$HOME`.

- [ ] **Step 4: Repoint the fetch destinations**

In `mise.toml` `[tasks.fetch]`, replace the `mkdir` line and the six `fetch_pinned` calls:

```bash
mkdir -p "$APP_DIR/cmakelib" zsh/custom/plugins
```

```bash
fetch_pinned "$APP_DIR/ohmyzsh" https://github.com/ohmyzsh/ohmyzsh.git "$OHMYZSH_REF"
# Oh My Zsh resolves custom plugins only under $ZSH_CUSTOM/plugins/, so this
# clones to its real load path (ZSH-A-7, ZSH-R-12). It is the one fetched
# source that stays inside the repository.
fetch_pinned zsh/custom/plugins/zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git "$AUTOSUGGEST_REF"
fetch_pinned "$APP_DIR/cmakelib/cmakelib" https://github.com/cmakelib/cmakelib.git "$CMLIB_REF"
fetch_pinned "$APP_DIR/cmakelib/cmakelib-component-cmconf"  https://github.com/cmakelib/cmakelib-component-cmconf.git  "$CMLIB_CMCONF_REF"
fetch_pinned "$APP_DIR/cmakelib/cmakelib-component-cmdef"   https://github.com/cmakelib/cmakelib-component-cmdef.git   "$CMLIB_CMDEF_REF"
fetch_pinned "$APP_DIR/cmakelib/cmakelib-component-cmutil"  https://github.com/cmakelib/cmakelib-component-cmutil.git  "$CMLIB_CMUTIL_REF"
fetch_pinned "$APP_DIR/cmakelib/cmakelib-component-storage" https://github.com/cmakelib/cmakelib-component-storage.git "$CMLIB_STORAGE_REF"
```

- [ ] **Step 5: Repoint the framework placeholder**

In `mise.toml` `[tasks.render]`, the ohmyzsh placeholder no longer points into the repository. `$APP_DIR` is exported by the entry point, so use it directly:

```bash
    sed -e "s|___OHMYZSH_PROJECT_DIR___|${APP_DIR}|g" \
```

- [ ] **Step 6: Drop the ignore entry**

Remove the `_vendor/` line from `.gitignore`.

- [ ] **Step 7: Fetch and verify**

```bash
./setup fetch
ls "$APP_DIR/cmakelib"
```

Expected: five directories — `cmakelib` and the four components.

- [ ] **Step 8: Rewrite GEN-R-3 with the stated exception**

In `docs/requirements/general.md`, replace GEN-R-3's first sentence and append the criterion:

```markdown
**GEN-R-3** Fetched sources SHALL be contained in the application directory
and SHALL NOT be committed, unless the consuming program resolves them only
from a fixed path inside the repository, in which case they SHALL be fetched
directly to that path and the constraint SHALL be recorded as an assumption
on the consuming tool. Orchestrator working state SHALL be contained in the
repository but SHALL NOT be committed. Installed artifacts SHALL be contained
in the application directory and SHALL NOT be committed. All are
machine-local and reproducible from the pins.

The exception has exactly one member: the autosuggestions plugin, earned by
ZSH-A-7 and recorded in ZSH-R-12.
```

Update GEN-D-7 and GEN-D-12 to match, and append to GEN-R-17a:

```markdown
`WEAKENED 2026-08-17`: the submodule refusal is implemented with a query that
is meaningful only for paths inside the repository, so for fetched sources
that now live in the application directory it cannot fire. The unregistered-
content and uncommitted-changes refusals still apply to those paths. The
requirement is not withdrawn; this records that one of its three guards does
not cover the relocated sources.
```

- [ ] **Step 9: Update the per-tool documents**

First confirm `docs/requirements/tool-cmakelib.md` needs no path edit:

```bash
grep -n "_vendor" docs/requirements/tool-cmakelib.md
```

Expected: no output. That document refers to "the component search base path"
abstractly rather than naming a location, so it survives the move unchanged.
If the grep does return a hit, repoint it to `<application
directory>/cmakelib/`.

In `docs/requirements/tool-zsh.md`, append to ZSH-R-12:

```markdown
As of 2026-08-17 this path is the single stated exception to GEN-R-3 rather
than an instance of its general case: every other fetched source now lives in
the application directory.
```

- [ ] **Step 10: Update the README's migration notes**

`README.md` carries two notes written for the earlier `vendor/` to `_vendor/`
rename. Both are now wrong in a new way, because `_vendor/` is itself retired.

Note 2 (around line 91) explains that a `zsh/zshrc` generated before the
rename names the old path and trips the render guard. Keep the note — the
guard still refuses after any template change — but replace its stated cause:
the generated file now predates the move of fetched content out of the
repository, not the `vendor/` rename.

Note 3 (around line 97) tells the reader to leave an orphaned `vendor/` tree
in place. Extend it to cover `_vendor/`, which is now orphaned the same way:
retired from `.gitignore`, still populated on any machine set up before this
change, and deliberately not deleted by any task (GEN-R-17). Point at the
cleanup command in the plan's final task rather than adding a task that
deletes it.

- [ ] **Step 11: Run the checks**

Run: `test/run.sh fetch fetch unprivileged`
Expected: PASS, all five assertions.

- [ ] **Step 12: Commit**

```bash
git add mise.toml .gitignore README.md test/checks-fetch.sh \
        docs/requirements/general.md docs/requirements/tool-cmakelib.md \
        docs/requirements/tool-zsh.md
git commit -m "feat: fetch runtime content into the application directory

cmakelib and its four components move to App/cmakelib/, ohmyzsh to
App/ohmyzsh/, and _vendor/ is retired. zsh-autosuggestions stays where it
is: Oh My Zsh resolves plugins only under its custom plugin directory
(ZSH-A-7), so GEN-R-3 gains a stated exception rather than moving wholesale.

config_root is no longer used in the pin file - it is now also the global
config, where that root defaults to \$HOME.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: One installed version per tool

The spec records this mechanism as unresolved (F-6): `mise prune --dry-run` reported it would uninstall the stale Go version, `mise prune` then reported only "pruned configuration links" and left it in place, and `mise uninstall go@1.23.3` removed it. **Establish the behaviour before writing the task.**

**Files:**
- Modify: `mise.toml` `[tasks.tools]`
- Modify: `test/checks-tools.sh`
- Modify: `docs/requirements/general.md` (new GEN-R-21)

**Interfaces:**
- Consumes: `App/<tool>/<version>/` layout from Task 4.

- [ ] **Step 1: Reproduce the ambiguity deliberately**

```bash
mise install go@1.25.13
mise ls --prunable
mise prune --dry-run
mise prune
mise ls --prunable
```

Record which command actually removes the extra version. `1.25.13` is used only as a scratch second version — it is not a pin and must not appear in `mise.toml`.

- [ ] **Step 2: Write the failing check**

Append to `test/checks-tools.sh`:

```bash
assert_cmd "exactly one go version installed" bash -c '
    [ "$(ls -1 "${APP_DIR}/go" | grep -c "^[0-9]*\.[0-9]*\.[0-9]*$")" -eq 1 ]
'
assert_cmd "exactly one cmake version installed" bash -c '
    [ "$(ls -1 "${APP_DIR}/cmake" | grep -c "^[0-9]*\.[0-9]*\.[0-9]*$")" -eq 1 ]
'
```

The `grep -c` pattern counts only full version directories; mise also creates
partial-version alias symlinks (`1`, `1.26`, `latest`) which are not separate
installs.

- [ ] **Step 3: Run it to verify it fails**

With the scratch version from Step 1 still installed:
Run: `test/run.sh tools tools unprivileged`
Expected: FAIL on `exactly one go version installed`.

- [ ] **Step 4: Add the pruning step to the tools task**

Using whichever invocation Step 1 proved effective:

```toml
[tasks.tools]
depends = ["preflight"]
run = """
set -euo pipefail
mise install
# Leaves exactly one version of each pinned tool installed (GEN-R-21). A
# superseded version is not a pin and not reachable from one; keeping it makes
# resolution ambiguous when no configuration is in scope.
mise prune
"""
```

If Step 1 showed `prune` does not remove tool versions, replace that line with the invocation that does, and record what was observed in a comment — the plan's assumption is explicitly untrusted here.

- [ ] **Step 5: Run the check to verify it passes**

Run: `test/run.sh tools tools unprivileged`
Expected: PASS.

- [ ] **Step 6: Record the requirement**

In `docs/requirements/general.md`:

```markdown
**GEN-R-21** Setup SHALL leave exactly one installed version of each pinned
tool. A superseded version is not reachable from any pin, and its presence
makes resolution ambiguous where no configuration is in scope.
```

With the verification row:

```markdown
| GEN-R-21 | After a pin bump and a setup run, exactly one version of the bumped tool is installed, and it is the pinned one |
```

- [ ] **Step 7: Verify the bump-and-prune cycle end to end**

```bash
mise install go@1.25.13   # simulate a superseded install
./setup tools
ls -1 "$APP_DIR/go"
```

Expected: only the pinned version and its alias symlinks remain.

- [ ] **Step 8: Commit**

```bash
git add mise.toml test/checks-tools.sh docs/requirements/general.md
git commit -m "feat: leave exactly one installed version per pinned tool

A superseded install is not reachable from any pin and makes resolution
ambiguous where no config is in scope - the failure mode that made the
shim approach report 'No version is set'.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Full regression and acceptance

**Files:**
- Modify: `test/checks-acceptance.sh`

- [ ] **Step 1: Add the layout acceptance assertions**

```bash
assert_cmd "one directory per managed tool" bash -c '
    for tool in go cmake cmakelib mise nvim ohmyzsh; do
        [ -d "${APP_DIR}/${tool}" ] || { echo "missing: ${tool}" >&2; exit 1; }
    done
'
assert_cmd "application root is not a dumping ground" bash -c '
    [ ! -e "${APP_DIR}/lib64" ] && [ ! -e "${APP_DIR}/share/nvim" ]
'
assert_cmd "no bare bin directory survives" bash -c '
    [ ! -e "${APP_DIR}/bin" ]
'
assert_cmd "the search path names exactly two APP_DIR entries" bash -c '
    [ "$(printf "%s\n" $PATH | tr ":" "\n" | grep -c "^${APP_DIR}/")" -eq 2 ] &&
    [ -d "${APP_DIR}/mise/bin" ] && [ -d "${APP_DIR}/nvim/bin" ]
'
```

- [ ] **Step 2: Run every check set, unprivileged**

```bash
for check in preflight tools fetch render link nvim docs; do
    test/run.sh "$check" "$check" unprivileged || echo "FAILED: $check"
done
```

Expected: all pass. `nvim` may need a retry on HTTP 429.

- [ ] **Step 3: Run the privileged sets**

```bash
test/run.sh bootstrap packages privileged
test/run.sh acceptance all privileged
```

- [ ] **Step 4: Verify idempotence (GEN-R-4)**

```bash
./setup
./setup
```

Expected: the second run reports no work and exits zero.

- [ ] **Step 5: Verify global resolution one final time**

```bash
cd "$HOME" && zsh -i -c 'go version; cmake --version | head -1; nvim --version | head -1'
```

Expected: all three report pinned versions from outside the repository.

- [ ] **Step 6: Commit**

```bash
git add test/checks-acceptance.sh
git commit -m "test: assert the one-directory-per-tool layout

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Hand the user the cleanup commands**

Stale paths from the previous layout are left in place deliberately (spec §7 — automatic deletion of paths an earlier version of this repository created is what GEN-R-17 refuses). Present these for the user to run themselves, after they have confirmed the new layout works:

```bash
rm -rf "$HOME/App/lib64"
rm -rf "$HOME/App/share/nvim"
rm -rf "$HOME/App/bin"
rm -rf "$HOME/App/mise/installs"
rm -rf "$HOME/App/system-config/_vendor"
```

`App/bin` goes as a whole now rather than just its `nvim` entry: after Task 5 the orchestrator lives in `App/mise/bin`, leaving the old directory with no occupant this repository owns. Confirm that before removing it — if anything unexpected is inside, remove the two known entries by name instead:

```bash
rm -f "$HOME/App/bin/mise" "$HOME/App/bin/nvim"
rmdir "$HOME/App/bin"
```

Each path is named explicitly; no globs (the repository's safety rule).

---

## Decisions confirmed after the spec was written

Both were open when the spec was drafted and were settled on 2026-08-17. Spec §8 records them.

- **ohmyzsh moves to `App/ohmyzsh/`** — Task 7 as written.
- **`App/bin/` is retired** — Task 5, added after the original eight-task draft. The orchestrator's binary moves to `App/mise/bin/mise`, which is what makes the one-directory-per-tool rule exceptionless.

No open items remain.
