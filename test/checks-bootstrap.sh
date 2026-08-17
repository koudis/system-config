assert_cmd  "mise is installed"            command -v mise
assert_cmd  "APP_DIR exists"               test -d "${APP_DIR:-$HOME/App}"
assert_cmd  "MISE_DATA_DIR under APP_DIR"  test -d "${APP_DIR:-$HOME/App}/mise"
# Replaces a vacuous `test ! -d "$HOME/Bin"`: nothing in this branch touches
# ~/Bin, whereas the orchestrator's own version pin is the one pin that used
# not to be enforced anywhere. Reads min_version out of mise.toml the same way
# ./setup does, so the installed binary and the declared pin cannot drift.
assert_cmd  "mise is at the pinned version" bash -c '
    pin=$(sed -n "s/^min_version[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
          /home/tester/work/mise.toml | head -1)
    [[ -n $pin && $(mise version | head -1) == *"$pin"* ]]'
assert_cmd  "mise finds repo config"       bash -c 'cd /home/tester/work && mise config ls | grep -q mise.toml'
assert_cmd  "preview mode runs"            bash -c 'cd /home/tester/work && mise run preview'
assert_cmd  "cmakelib env exported"        bash -c 'cd /home/tester/work && mise env | grep -q CMLIB_DIR'
assert_cmd  "preview-system mode runs"     bash -c 'cd /home/tester/work && mise run preview-system'
# grep -A5 would stay inside [tasks.preview]'s body only by coincidence of its
# current length; a shorter body would let the window bleed into
# [tasks.preview-system]'s own dnf line and fail for the wrong reason. awk
# extracts exactly the block between the two [tasks.*] headers instead.
assert_cmd  "preview names no dnf"         bash -c '
    ! awk "/^\[tasks\.preview\]\$/{f=1;next} /^\[/{f=0} f" \
        /home/tester/work/mise.toml | grep -q "manager dnf"'
