APP="${APP_DIR:-$HOME/App}"
# The pins are read out of mise.toml, never restated here (GEN-R-7). A literal
# in this file is a second pin location: commit 5c9a6a2 had to hand-edit these
# two lines during a Go bump, which is exactly the drift the single pin
# location exists to prevent. Same technique as test/checks-bootstrap.sh, and
# the empty-pin test is what stops a failed extraction from making the version
# assertion vacuous.
assert_cmd "cmake reports the pinned version" bash -c '
    pin=$(sed -n "s/^ *cmake *= *\"\([^\"]*\)\".*/\1/p" mise.toml | head -1)
    [[ -n $pin ]] && cmake --version | grep -qF "$pin"'
assert_cmd "go reports the pinned version" bash -c '
    pin=$(sed -n "s/^ *go *= *\"\([^\"]*\)\".*/\1/p" mise.toml | head -1)
    [[ -n $pin ]] && go version | grep -qF "go$pin"'
assert_path_under "cmake under APP_DIR"   cmake "$APP"
assert_path_under "go under APP_DIR"      go    "$APP"
# There was a `test ! -d "$HOME/Bin"` here. Nothing in this branch creates or
# removes ~/Bin, so it was vacuous in the container and false on any machine
# that happens to keep its own ~/Bin. The single-prefix requirement (GEN-R-1a)
# is what it meant to assert, and the two assert_path_under lines above assert
# exactly that, against the resolved binaries rather than against a directory
# name nobody writes to.
assert_cmd "go installs directly under APP_DIR" bash -c '
    [ -d "${APP_DIR}/go" ] && [ ! -d "${APP_DIR}/mise/installs/go" ]
'
assert_cmd "cmake installs directly under APP_DIR" bash -c '
    [ -d "${APP_DIR}/cmake" ] && [ ! -d "${APP_DIR}/mise/installs/cmake" ]
'
# GEN-R-21: exactly one full-version directory per pinned tool. mise also
# creates partial-version alias symlinks (1, 1.26, latest), which grep's
# anchored N.N.N pattern does not count as installs.
assert_cmd "exactly one go version installed" bash -c '
    [ "$(ls -1 "${APP_DIR}/go" | grep -Ec "^[0-9]+\.[0-9]+\.[0-9]+$")" -eq 1 ]
'
assert_cmd "exactly one cmake version installed" bash -c '
    [ "$(ls -1 "${APP_DIR}/cmake" | grep -Ec "^[0-9]+\.[0-9]+\.[0-9]+$")" -eq 1 ]
'

# GEN-R-21's radius, at the source. `prune --tools` with no tool arguments
# enumerates the whole installs directory - which is now the application
# directory - against mise's core backends and schedules for deletion any
# <tool>/<version> no trusted configuration pins, including directories this
# repository never created. The scope is the fix; these two lines are what
# stops it silently coming off.
assert_cmd "the prune step names the tools it may remove" bash -c '
    grep -qE "prune --tools \\\$pinned$" mise.toml
'
assert_cmd "the prune step is never invoked unscoped" bash -c '
    ! grep -qE "prune --tools[[:space:]]*$" mise.toml
'

# The same property end to end, and the reason it is last in this file: it
# creates a directory under APP_DIR shaped exactly like a mise-managed install
# of a core backend it does not pin, then runs the tools task again. The
# unscoped form deleted this in a dry run against a scratch tree; the scoped
# form must not touch it. `node` is chosen because it is a core backend name
# and this repository pins no node.
assert_cmd "a user directory shaped like a core tool survives the prune" bash -c '
    mkdir -p "${APP_DIR}/node/20.0.0"
    date > "${APP_DIR}/node/20.0.0/kept-by-the-user"
    ./setup tools >/dev/null 2>&1 &&
    [ -s "${APP_DIR}/node/20.0.0/kept-by-the-user" ]
'
