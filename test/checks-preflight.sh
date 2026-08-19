# Preflight gates only what the unprivileged tasks execute. zsh, fzf, direnv,
# ag, kitty and pynvim are deliberately absent from this list: they are runtime
# dependencies of the resulting shell, not of any task here, so blocking on them
# would refuse to run on a headless machine for no reason (spec section 4).
# mise tasks | grep prints a bare, unindented list here (no descriptions are
# set, so no columns to anchor against), but that format is not guaranteed.
# mise run --dry-run checks existence by exit code alone: 0 if the task
# resolves, non-zero ("no task <name> found") otherwise - no text to anchor to.
assert_cmd "preflight task exists"    bash -c 'cd /home/tester/work && mise run --dry-run preflight'
assert_cmd "git present"              command -v git
assert_cmd "curl present"             command -v curl
assert_cmd "gcc present"              command -v gcc
assert_cmd "make present"             command -v make
assert_cmd "ninja present"            command -v ninja
assert_cmd "msgfmt present"           command -v msgfmt
assert_cmd "flatpak present"          command -v flatpak
# The property under test for the whole unprivileged phase.
assert_cmd "sudo is absent"           bash -c '! command -v sudo'
