# APPS-R-12: the generated launcher that makes the VSCodium Flatpak reachable
# by name. Flatpak is absent from the container, so these assert what the task
# produces, not that the application starts - APPS-A-9's gap covers the install
# itself and this launcher inherits it.
launcher="${APP_DIR}/codium/bin/codium"

assert_cmd "launcher exists"        test -f "$launcher"
assert_cmd "launcher is executable" test -x "$launcher"

# GEN-R-1a: under the application directory, in a directory named after the
# tool. Resolution by name is the whole point, so it is asserted against PATH
# rather than against the path just spelled out above.
assert_cmd "codium resolves on PATH to the launcher" \
    bash -c '[[ "$(command -v codium)" == "$1" ]]' _ "$launcher"

# GEN-R-7: the identifier comes from CODIUM_APP, so a launcher naming anything
# else is a second location for that value.
assert_cmd "launcher names the declared identifier" \
    grep -qw "$CODIUM_APP" "$launcher"

# The reason this is a script and not an alias: it has to pass its arguments
# through, so that `codium file`, $EDITOR and any non-shell caller work.
assert_cmd "launcher forwards its arguments" \
    grep -qF '"$@"' "$launcher"

# GEN-R-1a's prohibition on a second install prefix. A user binary directory
# holding a rival copy is the defect that requirement exists to refuse.
assert_cmd "no launcher in a user binary directory" \
    test ! -e "$HOME/.local/bin/codium"
