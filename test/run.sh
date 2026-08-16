#!/usr/bin/env bash
set -euo pipefail
TASK="${1:?usage: test/run.sh <check-name> <mise-target>}"
# No default target: "all" pulls in the apps task, and that is roughly 15 GB of
# desktop applications no check set exercises. Every caller states its target.
TARGET="${2:?usage: test/run.sh <check-name> <mise-target>}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

podman build -t sysconfig-test -f "${REPO_ROOT}/test/Containerfile" "${REPO_ROOT}"

# label=disable avoids relabeling the bind-mount source (the host repo);
# the SELinux "Z" option would otherwise mutate the real working tree.
podman run --rm -i \
    --security-opt label=disable \
    --userns=keep-id \
    -v "${REPO_ROOT}:/home/tester/repo:ro" \
    sysconfig-test bash -lc "
        set -euo pipefail
        # A clone, not 'cp -r': the harness must test what is committed. A
        # recursive copy drags in gitignored host state - a .build tree whose
        # CMake cache holds host-absolute paths, populated vendor/ clones, an
        # already-rendered zsh/zshrc - which would let fetch, render and nvim
        # pass by reusing the host's work instead of doing their own. Cloning
        # also keeps a real .git, which the tasks need (git rev-parse
        # --show-toplevel) and the acceptance checks read (git ls-files -s,
        # git grep), so seeding from a plain 'git archive' export is not
        # enough. Uncommitted edits to tracked files are dropped on purpose.
        git clone --quiet --no-hardlinks /home/tester/repo /home/tester/work
        cd /home/tester/work
        ./setup ${TARGET}
        echo '--- second run (idempotence) ---'
        ./setup ${TARGET}
        export APP_DIR=\"\${APP_DIR:-\$HOME/App}\"
        # Mirrors ./setup's own MISE_DATA_DIR export (GEN-A-7): ./setup ran as a
        # child process above, so that export never reached this parent shell.
        # This re-derives the same value rather than redefining it, and never
        # runs outside throwaway container verification.
        export MISE_DATA_DIR=\"\$APP_DIR/mise\"
        PATH=\"\$APP_DIR/bin:\$PATH\"
        command -v mise >/dev/null && eval \"\$(mise env -s bash)\"
        source test/assert.sh
        source test/checks-${TASK}.sh
        finish
    "
