assert_cmd "ohmyzsh is a git work tree"  git -C vendor/ohmyzsh rev-parse --is-inside-work-tree
assert_cmd "ohmyzsh at pinned ref" \
    bash -c '[[ -n $OHMYZSH_REF && $(git -C vendor/ohmyzsh rev-parse HEAD) == "$OHMYZSH_REF" ]]'
assert_cmd "ohmyzsh not group-writable" \
    bash -c '[[ ! -w vendor/ohmyzsh || $(stat -c %A vendor/ohmyzsh | cut -c6) == "-" ]]'

# R9: zsh-autosuggestions is cloned to its real Oh My Zsh custom-plugin load
# path, not vendor/ - Oh My Zsh only resolves custom plugins there.
assert_cmd "autosuggestions is a git work tree" \
    git -C zsh/custom/plugins/zsh-autosuggestions rev-parse --is-inside-work-tree
assert_cmd "autosuggestions at pin" \
    bash -c '[[ -n $AUTOSUGGEST_REF && $(git -C zsh/custom/plugins/zsh-autosuggestions rev-parse HEAD) == "$AUTOSUGGEST_REF" ]]'

for c in cmakelib cmakelib-component-cmconf cmakelib-component-cmdef \
         cmakelib-component-cmutil cmakelib-component-storage; do
    assert_cmd "present: $c" test -d "vendor/$c"
done

assert_cmd "no ssh remotes anywhere" bash -c \
    '! grep -rq "git@github.com" vendor/*/.git/config zsh/custom/plugins/zsh-autosuggestions/.git/config'
