assert_cmd "ohmyzsh is a git work tree"  git -C "${APP_DIR}/ohmyzsh" rev-parse --is-inside-work-tree
assert_cmd "ohmyzsh at pinned ref" \
    bash -c '[[ -n $OHMYZSH_REF && $(git -C "${APP_DIR}/ohmyzsh" rev-parse HEAD) == "$OHMYZSH_REF" ]]'
assert_cmd "ohmyzsh not group-writable" \
    bash -c '[[ ! -w "${APP_DIR}/ohmyzsh" || $(stat -c %A "${APP_DIR}/ohmyzsh" | cut -c6) == "-" ]]'

# R9: zsh-autosuggestions is cloned to its real Oh My Zsh custom-plugin load
# path, not the application directory - Oh My Zsh only resolves custom
# plugins there.
assert_cmd "autosuggestions is a git work tree" \
    git -C zsh/custom/plugins/zsh-autosuggestions rev-parse --is-inside-work-tree
assert_cmd "autosuggestions at pin" \
    bash -c '[[ -n $AUTOSUGGEST_REF && $(git -C zsh/custom/plugins/zsh-autosuggestions rev-parse HEAD) == "$AUTOSUGGEST_REF" ]]'

# R26: assert every cmakelib component sits at its pinned ref too, resolved
# the same tag-or-SHA-aware way the fetch task uses (some pins, e.g.
# CMLIB_CMCONF_REF, are tag names rather than commit SHAs).
cmlib_dirs=(cmakelib cmakelib-component-cmconf cmakelib-component-cmdef \
            cmakelib-component-cmutil cmakelib-component-storage)
cmlib_ref_vars=(CMLIB_REF CMLIB_CMCONF_REF CMLIB_CMDEF_REF \
                CMLIB_CMUTIL_REF CMLIB_STORAGE_REF)
for i in "${!cmlib_dirs[@]}"; do
    c="${cmlib_dirs[$i]}"
    ref_var="${cmlib_ref_vars[$i]}"
    ref_val="${!ref_var}"
    assert_cmd "present: $c" test -d "${APP_DIR}/cmakelib/$c"
    assert_cmd "$c at pinned ref" bash -c \
        "[[ -n \"$ref_val\" && \$(git -C \"${APP_DIR}/cmakelib/$c\" rev-parse HEAD) == \
           \$(git -C \"${APP_DIR}/cmakelib/$c\" rev-parse --verify \"$ref_val^{commit}\") ]]"
done

assert_cmd "no ssh remotes anywhere" bash -c \
    '! grep -rq "git@github.com" "${APP_DIR}"/ohmyzsh/.git/config "${APP_DIR}"/cmakelib/*/.git/config zsh/custom/plugins/zsh-autosuggestions/.git/config'

assert_cmd "cmakelib holds the library and its components" bash -c '
    [ -d "${APP_DIR}/cmakelib/cmakelib" ] &&
    [ -d "${APP_DIR}/cmakelib/cmakelib-component-cmconf" ] &&
    [ -d "${APP_DIR}/cmakelib/cmakelib-component-storage" ]
'
assert_cmd "the vendored directory is gone" bash -c '[ ! -d _vendor ]'
assert_cmd "the fixed-path exception still holds" bash -c '
    [ -d zsh/custom/plugins/zsh-autosuggestions ]
'
assert_cmd "no {{config_root}} template use in the pin file" bash -c '
    ! grep -v "^[[:space:]]*#" mise.toml | grep -q "{{[[:space:]]*config_root"
'
