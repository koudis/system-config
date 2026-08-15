assert_cmd  "mise is installed"            command -v mise
assert_cmd  "APP_DIR exists"               test -d "${APP_DIR:-$HOME/App}"
assert_cmd  "MISE_DATA_DIR under APP_DIR"  test -d "${APP_DIR:-$HOME/App}/mise"
assert_cmd  "no legacy Bin prefix"         test ! -d "$HOME/Bin"
assert_cmd  "mise finds repo config"       bash -c 'cd /home/tester/work && mise config ls | grep -q mise.toml'
assert_cmd  "preview mode runs"            bash -c 'cd /home/tester/work && mise run preview'
assert_cmd  "cmakelib env exported"        bash -c 'cd /home/tester/work && mise env | grep -q CMLIB_DIR'
