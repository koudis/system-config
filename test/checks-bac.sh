APP="${APP_DIR:-$HOME/App}"
# BAC_REF is read out of mise.toml, never restated here - see the note in
# test/checks-tools.sh. This one reads the file directly, so a binary and an
# environment that agree with each other but not with the pin file still fails.
assert_cmd "bac reports the pinned ref" bash -c '
    pin=$(sed -n "s/^ *BAC_REF *= *\"\([^\"]*\)\".*/\1/p" mise.toml | head -1)
    [[ -n $pin ]] && bac --version | grep -qF "$pin"'
# BAC-R-11 in its observable form: the default when the link-time injection is
# missing is the literal "dev", so a restated or broken build recipe shows up
# here rather than as a build failure.
assert_cmd "no fallback version string" bash -c '! bac --version | grep -qw dev'
# BAC-R-3 / BAC-A-7: the engine is a runtime prerequisite of the sessions bac
# starts, never of building or invoking it. Pointing the standard Docker
# environment variable at a socket that cannot exist proves the claim wherever
# this runs, rather than resting on the harness image happening to carry no
# engine.
assert_cmd "the version query never contacts a daemon" bash -c '
    DOCKER_HOST=unix:///nonexistent/bac-check.sock bac --version'
assert_path_under "bac under APP_DIR"      bac "$APP"
assert_cmd "bac owns one directory under APP_DIR" bash -c '
    [ -x "${APP_DIR}/bac/bin/bac" ] && [ -d "${APP_DIR}/bac/src" ]
'
# Resolved the tag-or-SHA-aware way the fetch task uses, because BAC_REF is a
# tag rather than a commit SHA (see the cmakelib components in checks-fetch.sh).
assert_cmd "the checkout is at the pinned ref" bash -c '
    [[ -n $BAC_REF ]] &&
    [[ $(git -C "${APP_DIR}/bac/src" rev-parse HEAD) == \
       $(git -C "${APP_DIR}/bac/src" rev-parse --verify "$BAC_REF^{commit}") ]]'
# BAC-A-10: the build writes into the checkout and upstream ignores what it
# writes. A dirty checkout would be refused by refuse_if_dirty on the next pin
# bump, so this is the check that keeps a pin bump possible at all.
assert_cmd "the build leaves the checkout clean" bash -c '
    [[ -z $(git -C "${APP_DIR}/bac/src" status --porcelain) ]]'
# Same reasoning as the nvim stamp assertions (R27): the stamp must be rewritten
# from the current env by the ungated bac-stamp task on every run, not only when
# a build happens, or a pin change is invisible to the freshness gate.
assert_cmd "stamp matches current pin"    bash -c \
    '[[ "$(sed -n 1p .build/bac.version)" == "$BAC_REF" ]]'
assert_cmd "stamp matches current prefix" bash -c \
    '[[ "$(sed -n 2p .build/bac.version)" == "$APP_DIR" ]]'
assert_cmd "bac does not scatter into APP_DIR root" bash -c '
    [ ! -e "${APP_DIR}/bac-linux-amd64" ] && [ ! -e "${APP_DIR}/bac-linux-arm64" ]
'
