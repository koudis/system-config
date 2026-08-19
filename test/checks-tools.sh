APP="${APP_DIR:-$HOME/App}"
assert_cmd        "cmake reports 3.30.1"  bash -c 'cmake --version | grep -q 3.30.1'
assert_cmd        "go reports 1.26.6"     bash -c 'go version | grep -q go1.26.6'
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
