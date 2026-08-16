APP="${APP_DIR:-$HOME/App}"
assert_cmd        "nvim reports v0.11.6"   bash -c 'nvim --version | head -1 | grep -q "v0.11.6"'
assert_cmd        "no dev suffix"          bash -c '! nvim --version | head -1 | grep -q dev'
assert_cmd        "built RelWithDebInfo"   bash -c 'nvim --version | grep -q RelWithDebInfo'
assert_path_under "nvim under APP_DIR"     nvim "$APP"
# R27: the stamp must be rewritten from the current env on every run (by the
# ungated nvim-stamp task), not only when a build actually happens - this is
# what makes a NVIM_VERSION/APP_DIR change visible to the freshness gate at
# all. A regression that moves the write back inside the gated task body
# would still pass here on a from-scratch harness run, but this catches the
# more common slip: the stamp silently drifting from the declared pins.
assert_cmd        "stamp matches current pin"    bash -c \
    '[[ "$(sed -n 1p .build/nvim.version)" == "$NVIM_VERSION" ]]'
assert_cmd        "stamp matches current prefix" bash -c \
    '[[ "$(sed -n 2p .build/nvim.version)" == "$APP_DIR" ]]'
