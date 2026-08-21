assert_cmd "zsh installed"            command -v zsh
assert_cmd "fzf installed"            command -v fzf
assert_cmd "direnv installed"         command -v direnv
assert_cmd "ag installed"             command -v ag
assert_cmd "pynvim module present"    python3 -c 'import pynvim'
assert_cmd "ninja-build installed"    command -v ninja
assert_cmd "gettext installed"        command -v msgfmt
assert_cmd "glibc-gconv-extra"        rpm -q glibc-gconv-extra
# LUKS-R-2a: runtime prerequisites of luks-automount, declared as ordinary
# distribution packages. Neither is command-checkable in a way that means
# anything here - gnome-keyring's daemon needs a session - so both are asserted
# by rpm -q, the same way glibc-gconv-extra is above.
assert_cmd "cryptsetup installed"     rpm -q cryptsetup
assert_cmd "gnome-keyring installed"  rpm -q gnome-keyring
assert_cmd "login shell is zsh"       bash -c 'getent passwd tester | grep -q /bin/zsh'
# mise run --dry-run checks existence by exit code alone (see checks-preflight.sh).
assert_cmd "system task exists"       bash -c 'cd /home/tester/work && mise run --dry-run system'
assert_cmd "login-shell task exists"  bash -c 'cd /home/tester/work && mise run --dry-run login-shell'
