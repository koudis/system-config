assert_cmd "zsh installed"            command -v zsh
assert_cmd "fzf installed"            command -v fzf
assert_cmd "direnv installed"         command -v direnv
assert_cmd "ag installed"             command -v ag
assert_cmd "pynvim module present"    python3 -c 'import pynvim'
assert_cmd "ninja-build installed"    command -v ninja
assert_cmd "gettext installed"        command -v msgfmt
assert_cmd "glibc-gconv-extra"        rpm -q glibc-gconv-extra
assert_cmd "login shell is zsh"       bash -c 'getent passwd tester | grep -q /bin/zsh'
# mise run --dry-run checks existence by exit code alone (see checks-preflight.sh).
assert_cmd "system task exists"       bash -c 'cd /home/tester/work && mise run --dry-run system'
assert_cmd "login-shell task exists"  bash -c 'cd /home/tester/work && mise run --dry-run login-shell'
