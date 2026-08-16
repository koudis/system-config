#!/usr/bin/env bash
set -euo pipefail
USAGE="usage: test/run.sh <check-name> <mise-target> <privileged|unprivileged> [expect-fail]"
TASK="${1:?$USAGE}"
# No default target: "all" pulls in the apps task, and that is roughly 15 GB of
# desktop applications no check set exercises. Every caller states its target.
TARGET="${2:?$USAGE}"
# No default mode either, for the same reason the target has none: a silently
# defaulted image would let a check pass against the wrong machine.
MODE="${3:?$USAGE}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

case "$MODE" in
    privileged)   CONTAINERFILE="${REPO_ROOT}/test/Containerfile"
                  IMAGE=sysconfig-test ;;
    unprivileged) CONTAINERFILE="${REPO_ROOT}/test/Containerfile.nosudo"
                  IMAGE=sysconfig-test-nosudo ;;
    *)            echo "test/run.sh: mode must be privileged or unprivileged, got '$MODE'" >&2
                  exit 1 ;;
esac

podman build -t "$IMAGE" -f "$CONTAINERFILE" "${REPO_ROOT}"

# label=disable avoids relabeling the bind-mount source (the host repo);
# the SELinux "Z" option would otherwise mutate the real working tree.
podman run --rm -i \
    --security-opt label=disable \
    --userns=keep-id \
    -v "${REPO_ROOT}:/home/tester/repo:ro" \
    "$IMAGE" bash -lc "
        set -euo pipefail
        # A clone, not 'cp -r': the harness must test what is committed. A
        # recursive copy drags in gitignored host state - a .build tree whose
        # CMake cache holds host-absolute paths, populated _vendor/ clones, an
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
