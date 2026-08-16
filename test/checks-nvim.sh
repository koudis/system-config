APP="${APP_DIR:-$HOME/App}"
assert_cmd        "nvim reports v0.11.6"   bash -c 'nvim --version | head -1 | grep -q "v0.11.6"'
assert_cmd        "no dev suffix"          bash -c '! nvim --version | head -1 | grep -q dev'
assert_cmd        "built RelWithDebInfo"   bash -c 'nvim --version | grep -q RelWithDebInfo'
assert_path_under "nvim under APP_DIR"     nvim "$APP"
