assert_cmd "flatpak installed"     command -v flatpak
assert_cmd "flathub remote exists" bash -c 'flatpak remotes --user | grep -q flathub'
assert_cmd "flathub is unfiltered" bash -c '! flatpak remotes --user --show-details | grep -qi "filter"'
assert_cmd "no system remote added" bash -c '! flatpak remotes --system | grep -q flathub'
# APPS-R-11: FLATPAK_APPS is read from the mise env this check set inherits
# (test/run.sh evals `mise env -s bash` before sourcing it), not restated here -
# a hardcoded copy would be a second location for the same list (GEN-R-7) and
# could drift from mise.toml silently. Guard the count too: an empty or
# unexported FLATPAK_APPS would otherwise make the loop below vacuously pass.
assert_cmd "seventeen identifiers exported" bash -c '[[ $(wc -w <<<"$FLATPAK_APPS") == 17 ]]'
for app in $FLATPAK_APPS; do
    assert_cmd "resolvable: $app" flatpak remote-info --user flathub "$app"
done
