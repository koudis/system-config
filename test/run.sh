#!/usr/bin/env bash
set -euo pipefail
TASK="${1:?usage: test/run.sh <task-name>}"
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
        cp -r /home/tester/repo /home/tester/work
        cd /home/tester/work
        ./setup
        echo '--- second run (idempotence) ---'
        ./setup
        export APP_DIR=\"\${APP_DIR:-\$HOME/App}\"
        PATH=\"\$APP_DIR/bin:\$PATH\"
        command -v mise >/dev/null && eval \"\$(mise env -s bash)\"
        source test/assert.sh
        source test/checks-${TASK}.sh
        finish
    "
