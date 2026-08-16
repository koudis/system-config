APP="${APP_DIR:-$HOME/App}"
assert_cmd        "cmake reports 3.30.1"  bash -c 'cmake --version | grep -q 3.30.1'
assert_cmd        "go reports 1.23.3"     bash -c 'go version | grep -q go1.23.3'
assert_path_under "cmake under APP_DIR"   cmake "$APP"
assert_path_under "go under APP_DIR"      go    "$APP"
assert_cmd        "no Bin prefix"         test ! -d "$HOME/Bin"
