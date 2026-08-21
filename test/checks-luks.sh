# LUKS_REF is read out of mise.toml, never restated here - see the note in
# test/checks-tools.sh. Unlike bac there is no version the binary reports
# itself (LUKS-A-4), so this holds the artifact against the pin through the Go
# toolchain's build metadata instead: the binary reports no version of its own,
# but the toolchain stamps the source revision into it regardless.
assert_cmd "the staged binary carries the pinned commit" bash -c '
    rev=$(git -C "${APP_DIR}/luks-automount/src" rev-parse --verify "$LUKS_REF^{commit}") &&
    go version -m "${APP_DIR}/luks-automount/bin/luks-automount" | grep -qF "vcs.revision=$rev"'
assert_cmd "the staged binary runs" bash -c '
    "${APP_DIR}/luks-automount/bin/luks-automount" --help'
assert_cmd "luks-automount owns one directory under APP_DIR" bash -c '
    [ -x "${APP_DIR}/luks-automount/bin/luks-automount" ] &&
    [ -d "${APP_DIR}/luks-automount/src" ]
'
# LUKS-R-9's second half: the application root gains nothing beyond the two
# subdirectories the tool is allowed. Unlike bac, this build's stray-output
# risk lands inside src/ (LUKS-A-9), not the application root, so this checks
# the tool's own directory rather than APP_DIR's.
assert_cmd "luks-automount adds nothing beside src and bin" bash -c '
    [[ "$(ls -A "${APP_DIR}/luks-automount" | sort | tr "\n" " ")" == "bin src " ]]'
# Resolved the tag-or-SHA-aware way the fetch task uses, because LUKS_REF is a
# tag rather than a commit SHA (see the cmakelib components in checks-fetch.sh).
assert_cmd "the checkout is at the pinned ref" bash -c '
    [[ -n $LUKS_REF ]] &&
    [[ $(git -C "${APP_DIR}/luks-automount/src" rev-parse HEAD) == \
       $(git -C "${APP_DIR}/luks-automount/src" rev-parse --verify "$LUKS_REF^{commit}") ]]'
# LUKS-A-9 / LUKS-R-11 in their observable form: upstream's ignore rules cover
# the documented build command's output but not the release recipe's, so a
# build switched to the recipe shows up here as a dirty checkout - which is
# what would refuse the next pin bump through refuse_if_dirty.
assert_cmd "the build leaves the checkout clean" bash -c '
    [[ -z $(git -C "${APP_DIR}/luks-automount/src" status --porcelain) ]]'
# Same reasoning as the nvim and bac stamp assertions (GEN-R-18): the stamp must
# be rewritten from the current env by the ungated luks-stamp task on every run,
# not only when a build happens, or a pin change is invisible to the gate.
assert_cmd "stamp matches current pin"    bash -c \
    '[[ "$(sed -n 1p .build/luks.version)" == "$LUKS_REF" ]]'
assert_cmd "stamp matches current prefix" bash -c \
    '[[ "$(sed -n 2p .build/luks.version)" == "$APP_DIR" ]]'
# LUKS-R-8: the staging directory is deliberately not on the search path, so the
# bare name must not resolve. The operational copy lives at a fixed system path
# which this run must also have left alone.
assert_cmd "the staging directory is not on the search path" bash -c '
    ! command -v luks-automount'
# LUKS-R-3, LUKS-A-8, LUKS-R-5: the unprivileged phase installs nothing
# system-wide. All three paths upstream's installer writes stay absent.
assert_cmd "the unprivileged phase installs nothing system-wide" bash -c '
    [ ! -e /usr/local/bin/luks-automount ] &&
    [ ! -e /etc/sudoers.d/luks-automount ] &&
    [ ! -e "$HOME/.config/systemd/user/luks-automount.service" ]'
# LUKS-R-6, LUKS-R-7: the tool's own configuration file is machine-local state
# this repository neither creates nor reads, and nothing outside this tool's own
# tasks names it.
assert_cmd "setup does not touch the tool configuration directory" bash -c '
    [ ! -e "$HOME/.config/luks-automount" ]'
# LUKS-R-10: one fetch path, the shared guarded one, so GEN-R-17a's guards apply
# unchanged. A second, unguarded clone added later would show up here.
assert_cmd "the checkout has exactly one fetch site" bash -c '
    [[ $(grep -cF "fetch_pinned \"\$APP_DIR/luks-automount/src\"" mise.toml) -eq 1 ]]'

# LUKS-R-4. Only the absent branch is reachable here: /usr/local/bin is
# root-owned and this image has no sudo, so neither the differing nor the
# identical branch can be staged. Both are verified on a real machine instead,
# and the verification table in the requirements document says so.
#
# Two invocations captured up front, then asserted three ways. Each ./setup
# re-traverses this task's declared predecessors - fetch reaches the network,
# tools runs an install and a prune - so calling it once per assertion would
# multiply that work for nothing. The `|| rc=$?` form is required rather than
# stylistic: this file is sourced under `set -e`, where a bare command
# substitution that exits non-zero would abort the whole run before any
# assertion reported.
notice_rc=0
notice_out=$(./setup luks-notice 2>&1) || notice_rc=$?
notice_again=$(./setup luks-notice 2>&1) || true

assert_cmd "the notice names the install command when nothing is installed" \
    bash -c 'grep -qF "$1" <<< "$2"' _ \
    "${APP_DIR}/luks-automount/bin/luks-automount install" "$notice_out"
# A fresh machine has not run the one-time step by construction, so the notice
# firing must not be a failure - it would fail setup on exactly the machine
# setup exists to configure.
assert_cmd "the notice exits zero when nothing is installed" \
    bash -c '[ "$1" -eq 0 ]' _ "$notice_rc"
# The notice is ungated on purpose: the build it follows is freshness-gated, so
# on a second run the build is skipped and a message printed from inside it
# would not print. Requiring the text on the second invocation too is what
# distinguishes the two shapes.
assert_cmd "the notice still fires on a repeat run" \
    bash -c 'grep -qF "luks-automount install" <<< "$1"' _ "$notice_again"
