APP="${APP_DIR:-$HOME/App}"
# NVIM_VERSION is read out of mise.toml, never restated here - see the note in
# test/checks-tools.sh. The stamp assertions further down compare against the
# same pin through $NVIM_VERSION in the environment; this one reads the file
# directly, so a stamp and an environment that agree with each other but not
# with the pin file still fails.
assert_cmd "nvim reports the pinned version" bash -c '
    pin=$(sed -n "s/^ *NVIM_VERSION *= *\"\([^\"]*\)\".*/\1/p" mise.toml | head -1)
    [[ -n $pin ]] && nvim --version | head -1 | grep -qF "$pin"'
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
assert_cmd "nvim owns one directory under APP_DIR" bash -c '
    [ -x "${APP_DIR}/nvim/bin/nvim" ]
'
assert_cmd "nvim does not scatter into APP_DIR root" bash -c '
    [ ! -e "${APP_DIR}/lib64" ] && [ ! -e "${APP_DIR}/share/nvim" ]
'
