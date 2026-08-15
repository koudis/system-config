#!/usr/bin/env bash
# Assertion helpers. Sourced by the in-container test run.
FAILED=0

assert_cmd() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf 'PASS  %s\n' "$desc"
    else
        printf 'FAIL  %s  (command: %s)\n' "$desc" "$*"; FAILED=1
    fi
}

assert_path_under() {
    local desc="$1" binary="$2" prefix="$3"
    local resolved; resolved=$(command -v "$binary" 2>/dev/null)
    if [[ -n $resolved && $resolved == "$prefix"* ]]; then
        printf 'PASS  %s (%s)\n' "$desc" "$resolved"
    else
        printf 'FAIL  %s  (%s resolved to %s, expected under %s)\n' \
            "$desc" "$binary" "${resolved:-<not found>}" "$prefix"; FAILED=1
    fi
}

assert_absent() {
    local desc="$1" pattern="$2" file="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        printf 'FAIL  %s  (%s still present in %s)\n' "$desc" "$pattern" "$file"; FAILED=1
    else
        printf 'PASS  %s\n' "$desc"
    fi
}

finish() { [[ $FAILED -eq 0 ]] && printf '\nALL CHECKS PASSED\n' || printf '\nCHECKS FAILED\n'; exit $FAILED; }
