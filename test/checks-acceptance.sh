# Spec section 10 criteria that no single tool task owns: the end state of the
# migration itself. Most checks read the repository rather than the installed
# system, but not all of them: the layout and search-path checks below read the
# application directory, and the login-shell checks read the deployed profile,
# so this set does have a target it must be run against. It is the one that
# populates every managed tool's directory without pulling in the desktop
# applications:
#
#   test/run.sh acceptance "nvim ::: bac ::: link" unprivileged

# Criterion 3. `git ls-files -s`, not `git submodule status`, is the primary
# test: it sees a gitlink whether or not `.gitmodules` declares one, and an
# undeclared gitlink is exactly the defect this migration had (CMLIB-A-1).
assert_cmd "no submodule gitlinks" \
    bash -c '! git ls-files -s | grep -q "^160000"'
# An orphaned gitlink makes this command exit non-zero with empty output, so
# emptiness alone would pass while broken. The exit status is half the check.
assert_cmd "git submodule status silent and successful" \
    bash -c 'out=$(git submodule status) && [[ -z $out ]]'
assert_cmd "no .gitmodules" test ! -f .gitmodules

assert_cmd "no legacy scripts" \
    bash -c '[[ -z $(git ls-files "*/setup.sh" "*/install_deps.sh" lib.sh setup.sh) ]]'

# Every content grep below excludes this file. `git grep` searches tracked
# files, and the patterns being searched for are spelled out here verbatim, so
# an included check file matches its own regex and reports a violation that
# does not exist. Two of the three are currently out of scope anyway by their
# narrower pathspecs; they carry the exclusion so that widening a pathspec
# later cannot silently reintroduce the self-match.

# Criterion 14 says "anywhere in the repository", so this scans every tracked
# file rather than mise.toml and ./setup alone - the conditionals it has to
# catch lived in the shell scripts, which those two patterns never covered.
# docs/ is excluded because the requirement documents necessarily quote the
# constructs they forbid.
assert_cmd "no OS conditionals" \
    bash -c '! git grep -qiE "OS_NAME|if debian|apt install" -- ":!docs/" ":!test/checks-acceptance.sh"'

assert_cmd "no hardcoded username" \
    bash -c '! git grep -q "/home/h" -- "*/template/*" "*.toml" ":!test/checks-acceptance.sh"'
assert_cmd "no ssh urls" \
    bash -c '! git grep -q "git@github.com" -- "*.toml" setup ":!test/checks-acceptance.sh"'

assert_cmd "every tool has a requirements document" \
    bash -c 'for t in zsh neovim cmake cmakelib go kitty desktop-apps bootstrap-ai-coding; do
                 test -f "docs/requirements/tool-$t.md" || exit 1
             done'

# The end-state layout: eight earlier tasks moved every managed tool under
# its own name inside APP_DIR and retired the shared App/bin/. These read the
# installed application directory, not the repository, so they need a target
# that actually populates it (unlike every check above).
assert_cmd "one directory per managed tool" bash -c '
    for tool in go cmake cmakelib mise nvim ohmyzsh bac; do
        [ -d "${APP_DIR}/${tool}" ] || { echo "missing: ${tool}" >&2; exit 1; }
    done
'
assert_cmd "application root is not a dumping ground" bash -c '
    [ ! -e "${APP_DIR}/lib64" ] && [ ! -e "${APP_DIR}/share/nvim" ]
'
assert_cmd "no bare bin directory survives" bash -c '
    [ ! -e "${APP_DIR}/bin" ]
'
# A blanket count of ${APP_DIR}/-prefixed PATH entries was tried here first and
# rejected: MISE_INSTALLS_DIR is the application directory now, so the tool
# bin directories mise injects for [tools] - $APP_DIR/cmake/<version>/bin,
# $APP_DIR/go/<version>/bin - legitimately live under it too. That is
# orchestrator resolution working correctly, not a violation of it; every
# pinned tool except mise, nvim and bac is meant to be reached that way rather
# than by path. A raw count therefore does not mean what it would
# have meant before MISE_INSTALLS_DIR moved: it is not evidence of anything
# this repository forbids. What the spec actually claims is narrower - that
# THIS REPOSITORY's own entries are on PATH and exist, and that the
# retired shared bin directory is gone from both PATH and disk. That splits
# into the two checks below; the repository's own export naming exactly those
# entries and no others is asserted separately against the rendered profile in
# test/checks-render.sh, which is where that export actually lives.
assert_cmd "the repository's own bin directories are on PATH and exist" bash -c '
    for own in mise nvim bac; do
        [ -d "${APP_DIR}/${own}/bin" ] || exit 1
        printf "%s\n" $PATH | tr ":" "\n" | grep -qxF "${APP_DIR}/${own}/bin" || exit 1
    done
'
assert_cmd "the retired shared bin directory is gone from disk and PATH" bash -c '
    [ ! -e "${APP_DIR}/bin" ] &&
    ! printf "%s\n" $PATH | tr ":" "\n" | grep -qxF "${APP_DIR}/bin"
'

# GEN-A-13's verification row promises that searching the task table for a bare
# orchestrator invocation returns nothing. This is that search. Only task
# bodies are scanned: [env]'s ORCHESTRATOR_BIN necessarily ends in the binary's
# own name, and the surrounding comments necessarily discuss the thing they
# forbid. A bare invocation is the command name followed by whitespace and not
# preceded by a path separator or a word character, so `$APP_DIR/mise/bin/mise`,
# `mise.toml` and `zshrc.mise-new` are all correctly ignored.
task_bodies=$(awk '
    /^run = """$/ { body = 1; next }
    /^"""$/       { body = 0; next }
    /^run = /     { print; next }
    body          { print }
' mise.toml | sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//')
assert_cmd "no task body invokes a bare orchestrator" \
    bash -c '! grep -qE "(^|[^-_/[:alnum:].])mise[[:space:]]" <<< "$1"' _ "$task_bodies"

# GEN-R-16's second and third observables. The first one is the login-shell
# check further down.
assert_cmd "the configuration assigns neither process-start variable" bash -c '
    ! grep -qE "^[[:space:]]*(MISE_DATA_DIR|MISE_INSTALLS_DIR)[[:space:]]*=" mise.toml
'
# Named through its absolute path deliberately: the point is that the binary
# runs and then refuses, not that it cannot be found.
assert_cmd "the orchestrator refuses to parse its configuration without APP_DIR" bash -c '
    ! env -u APP_DIR "${APP_DIR}/mise/bin/mise" tasks ls
'

# Spec section 6's "Global visibility" and "No system fallthrough" rows, and
# with them GO-R-2 and ZSH-R-15, both of which say "outside this repository".
# Everything else in the harness runs with cwd inside the clone and with
# test/run.sh's own MISE_INSTALLS_DIR/MISE_DATA_DIR exports in scope, so
# configuration is found by upward walk and MISE_GLOBAL_CONFIG_FILE is never
# exercised. These start a real login shell instead:
#
#   - `env -i` drops every variable test/run.sh exported, so the only thing
#     that can set them again is the rendered profile the link task installed
#     at ~/.zshrc. HOME, TERM and PATH are all that is passed back in.
#   - `cd "$HOME"` in a subshell puts it outside the repository, where the
#     upward walk finds nothing and only the global configuration can answer.
#   - The decoy directory is first on PATH and holds executables named after
#     the pinned tools that report a version no pin names. Without it the
#     container's own lack of a system cmake would make "resolves the pinned
#     one rather than the system one" pass for the wrong reason; with it, a
#     profile that failed to activate the orchestrator resolves the decoy and
#     the check fails.
#   - `timeout` because a login shell that stops on a prompt would otherwise
#     wedge the run rather than fail it.
decoy_dir=$(mktemp -d)
for decoy in cmake go; do
    printf '#!/bin/sh\necho "%s version 0.0.0-decoy"\n' "$decoy" > "$decoy_dir/$decoy"
    chmod +x "$decoy_dir/$decoy"
done

login_shell() {
    ( cd "$HOME" && timeout 120 env -i HOME="$HOME" TERM=dumb \
        PATH="$decoy_dir:/usr/bin:/bin" zsh -l -i -c "$1" 2>/dev/null )
}

login_resolves_pinned() {
    local tool="$1" version_cmd="$2" pin out
    pin=$(sed -n "s/^ *$tool *= *\"\([^\"]*\)\".*/\1/p" mise.toml | head -1)
    [[ -n $pin ]] || return 1
    out=$(login_shell "command -v $tool; $version_cmd") || return 1
    grep -qF "$pin"             <<< "$out" || return 1
    grep -qF "$APP_DIR/$tool/"  <<< "$out" || return 1
    ! grep -q decoy <<< "$out"
}

assert_cmd "a login shell outside the repository resolves the pinned cmake" \
    login_resolves_pinned cmake "cmake --version"
assert_cmd "a login shell outside the repository resolves the pinned go" \
    login_resolves_pinned go "go version"

# GEN-R-16's first observable, on the same shell: a session that exported
# nothing itself still reports both orchestrator directories under APP_DIR.
# Labelled and matched whole-line rather than by position: some Oh My Zsh
# plugins report a missing optional dependency (fzf, direnv, ~/.ssh) on stdout
# rather than stderr, so the values are not the first lines of the output.
login_places_orchestrator_dirs() {
    local out
    out=$(login_shell 'printf "data=%s\ninstalls=%s\n" "$MISE_DATA_DIR" "$MISE_INSTALLS_DIR"') || return 1
    grep -qxF "data=$APP_DIR/mise" <<< "$out" &&
    grep -qxF "installs=$APP_DIR" <<< "$out"
}
assert_cmd "a login shell places both orchestrator directories under APP_DIR" \
    login_places_orchestrator_dirs
