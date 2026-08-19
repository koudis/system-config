# GEN-R-20: the requirements set indexes pins, it never restates their values.
# Every value in the pin file is searched for across docs/requirements/; a hit
# means a second copy exists and will go stale, which is what happened to the
# Go pin at 1.23.3.
assert_cmd "no requirements doc restates a pinned value" bash -c '
    fail=0
    while IFS= read -r value; do
        [ -z "$value" ] && continue
        if grep -rqF "$value" docs/requirements/; then
            echo "restated pin value: $value" >&2
            fail=1
        fi
        # A 40-hex commit SHA is also restated in its short (7-char) form,
        # e.g. `3bd355a` for `3bd355abf8...` - the same pin, and it goes
        # stale exactly like the full value would.
        if [[ "$value" =~ ^[0-9a-f]{40}$ ]] && grep -rqF "${value:0:7}" docs/requirements/; then
            echo "restated pin value (abbreviated): ${value:0:7}" >&2
            fail=1
        fi
    done <<< "$(grep -v "^min_version" mise.toml \
                | sed -n "s/^[A-Za-z_]* *= *\"\([^\"]*\)\".*/\1/p" \
                | grep -E "^(v?[0-9]+\.[0-9]+|[0-9a-f]{40})")"
    # min_version is excluded above: docs cite the orchestrator release only as
    # the platform a dated observation was made against ("VERIFIED - observed
    # against mise 2026.8.6"), which must not change when the pin bumps.
    [ "$fail" -eq 0 ]
'
assert_cmd "every registry key resolves in the pin file" bash -c '
    fail=0
    for key in min_version cmake go NVIM_VERSION OHMYZSH_REF AUTOSUGGEST_REF \
               CMLIB_REF CMLIB_CMCONF_REF CMLIB_CMDEF_REF CMLIB_CMUTIL_REF \
               CMLIB_STORAGE_REF; do
        grep -qE "^ *$key *=" mise.toml || { echo "missing key: $key" >&2; fail=1; }
    done
    [ "$fail" -eq 0 ]
'
