# GEN-R-22: the steps setup deliberately leaves to the user are named at the end
# of a run, and only while they are still outstanding. The container satisfies
# none of the four by construction - no container engine, no docker group, no
# SSH key pair, no installed luks-automount - so a bare run must name all four.
#
#   test/run.sh manual manual unprivileged
#
# The `|| rc=$?` form is required rather than stylistic: this file is sourced
# under `set -e`, where a bare command substitution that exits non-zero would
# abort the whole run before any assertion reported.

notice_rc=0
notice_out=$(./setup manual 2>&1) || notice_rc=$?

# A fresh machine satisfies none of these by construction, so the notice firing
# must not be a failure - it would fail setup on exactly the machine setup
# exists to configure.
assert_cmd "the notice exits zero with every step outstanding" \
    bash -c '[ "$1" -eq 0 ]' _ "$notice_rc"

assert_cmd "the notice names the container engine step" \
    bash -c 'grep -qF "systemctl enable --now docker" <<< "$1"' _ "$notice_out"
assert_cmd "the notice names the docker group step" \
    bash -c 'grep -qF "usermod -aG docker" <<< "$1"' _ "$notice_out"
assert_cmd "the notice names the SSH key step" \
    bash -c 'grep -qF "ssh-keygen" <<< "$1"' _ "$notice_out"
assert_cmd "the notice names the luks-automount install command" \
    bash -c 'grep -qF "$1" <<< "$2"' _ \
    "${APP_DIR}/luks-automount/bin/luks-automount install" "$notice_out"

# The engine and the group are independent conditions with different fixes
# (BAC-R-4), so each is named on its own rather than folded into one docker
# step. A machine with a running engine and no group membership must be told
# the one thing it needs, not both.
assert_cmd "the engine and the group are reported as separate steps" \
    bash -c '[ "$(grep -c "^setup:   docker" <<< "$1")" -eq 2 ]' _ "$notice_out"

# The count in the header is what makes the notice readable at a glance, and it
# is also the cheapest way to prove the steps are counted rather than printed
# unconditionally.
assert_cmd "the header counts the outstanding steps" \
    bash -c 'grep -qE "^setup: 4 manual steps remain" <<< "$1"' _ "$notice_out"

# The notice is ungated on purpose: the build it follows is freshness-gated, so
# on a second run the build is skipped and a message printed from inside it
# would not print. Requiring the text on a second invocation too is what
# distinguishes the two shapes.
notice_again=$(./setup manual 2>&1) || true
assert_cmd "the notice still fires on a repeat run" \
    bash -c 'grep -qF "luks-automount install" <<< "$1"' _ "$notice_again"

# A step that cannot fall silent is not a notice, it is a banner. Satisfying the
# one condition reachable inside the container proves both halves at once: that
# step stops being named, the others keep being named, and the count drops.
#
# Only the SSH step is reachable here. The engine and the group need machine
# state no unprivileged container can produce, and the luks step compares
# against /usr/local/bin, which is not writable in this image - so those three
# are covered by the naming assertions above and by their own tool's checks.
key=$HOME/.ssh/id_ed25519.pub
mkdir -p "$HOME/.ssh"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test@example\n' > "$key"
with_key=$(./setup manual 2>&1) || true
rm -f "$key"

assert_cmd "the SSH step falls silent once a public key exists" \
    bash -c '! grep -qF "ssh-keygen" <<< "$1"' _ "$with_key"
assert_cmd "satisfying one step leaves the others named" \
    bash -c 'grep -qF "luks-automount install" <<< "$1"' _ "$with_key"
assert_cmd "satisfying one step drops the header count" \
    bash -c 'grep -qE "^setup: 3 manual steps remain" <<< "$1"' _ "$with_key"

# GEN-R-22's placement half. The notice is attached to [tasks.all] with
# depends_post, so it runs after everything else in a full run and does not fire
# for a single unrelated target - `./setup link` must stay silent about it.
link_out=$(./setup link 2>&1) || true
assert_cmd "an unrelated target does not print the notice" \
    bash -c '! grep -qF "manual step" <<< "$1"' _ "$link_out"

# The per-tool notice it replaced must be gone rather than left alongside it,
# or the luks step is reported twice on every run.
assert_cmd "the retired per-tool notice task is gone" \
    bash -c '! grep -q "^\[tasks.luks-notice\]" mise.toml'
assert_cmd "nothing still depends on the retired task" \
    bash -c '! grep -q "luks-notice" mise.toml'
