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
EXPECT="${4:-}"
if [ -n "$EXPECT" ] && [ "$EXPECT" != expect-fail ]; then
    echo "test/run.sh: fourth argument must be expect-fail if given, got '$EXPECT'" >&2
    exit 1
fi
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
    -e EXPECT_FAIL="$EXPECT" \
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
        if [ \"\$EXPECT_FAIL\" = expect-fail ]; then
            # One run, not two: a failing setup has no second run to compare
            # for idempotence.
            if ./setup ${TARGET} >/tmp/setup.log 2>&1; then
                echo 'FAIL  setup succeeded but expect-fail was requested'; exit 1
            fi
            grep -q 'missing required commands' /tmp/setup.log || {
                echo 'FAIL  setup failed without the preflight message'
                cat /tmp/setup.log
                exit 1
            }
            echo 'PASS  setup failed with the preflight message'
        else
            ./setup ${TARGET}
            echo '--- second run (idempotence) ---'
            ./setup ${TARGET}
        fi
        export APP_DIR=\"\${APP_DIR:-\$HOME/App}\"
        # Mirrors ./setup's own MISE_DATA_DIR and MISE_INSTALLS_DIR exports
        # (GEN-A-7): ./setup ran as a child process above, so those exports
        # never reached this parent shell. This re-derives the same values
        # rather than redefining them, and never runs outside throwaway
        # container verification.
        export MISE_DATA_DIR=\"\$APP_DIR/mise\"
        export MISE_INSTALLS_DIR=\"\$APP_DIR\"
        PATH=\"\$APP_DIR/bin:\$PATH\"
        command -v mise >/dev/null && eval \"\$(mise env -s bash)\"
        # mise env -s bash recomputes PATH the same way it does for any task
        # body (GEN-A-13): it strips every inherited entry under the installs
        # directory, which now includes \$APP_DIR/bin itself, so mise
        # disappears from PATH the moment the eval above runs. Re-assert it
        # rather than skip the eval, which is still needed to pick up [env]
        # (FLATPAK_APPS, CMLIB_DIR, ...) for the checks below.
        PATH=\"\$APP_DIR/bin:\$PATH\"
        source test/assert.sh
        source test/checks-${TASK}.sh
        finish
    "
