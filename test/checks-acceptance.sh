# Spec section 10 criteria that no single tool task owns: the end state of the
# migration itself. Every check reads the repository, not the installed system,
# so the mise target this runs against is immaterial.

# Criterion 3. `git ls-files -s`, not `git submodule status`, is the primary
# test: it sees a gitlink whether or not `.gitmodules` declares one, and an
# undeclared gitlink is exactly the defect this migration had (CMLIB-A-1).
assert_cmd "no submodule gitlinks" \
    bash -c '! git ls-files -s | grep -q "^160000"'
# An orphaned gitlink makes this command exit non-zero with empty output, so
# emptiness alone would pass while broken. The exit status is half the check.
assert_cmd "git submodule status silent and successful" \
    bash -c 'out=$(git submodule status) && [[ -z $out ]]'
assert_cmd "no .gitmodules" test ! -f .gitmodules

assert_cmd "no legacy scripts" \
    bash -c '[[ -z $(git ls-files "*/setup.sh" "*/install_deps.sh" lib.sh setup.sh) ]]'

# Every content grep below excludes this file. `git grep` searches tracked
# files, and the patterns being searched for are spelled out here verbatim, so
# an included check file matches its own regex and reports a violation that
# does not exist. Two of the three are currently out of scope anyway by their
# narrower pathspecs; they carry the exclusion so that widening a pathspec
# later cannot silently reintroduce the self-match.

# Criterion 14 says "anywhere in the repository", so this scans every tracked
# file rather than mise.toml and ./setup alone - the conditionals it has to
# catch lived in the shell scripts, which those two patterns never covered.
# docs/ is excluded because the requirement documents necessarily quote the
# constructs they forbid.
assert_cmd "no OS conditionals" \
    bash -c '! git grep -qiE "OS_NAME|if debian|apt install" -- ":!docs/" ":!test/checks-acceptance.sh"'

assert_cmd "no hardcoded username" \
    bash -c '! git grep -q "/home/h" -- "*/template/*" "*.toml" ":!test/checks-acceptance.sh"'
assert_cmd "no ssh urls" \
    bash -c '! git grep -q "git@github.com" -- "*.toml" setup ":!test/checks-acceptance.sh"'

assert_cmd "every tool has a requirements document" \
    bash -c 'for t in zsh neovim cmake cmakelib go kitty desktop-apps; do
                 test -f "docs/requirements/tool-$t.md" || exit 1
             done'

# The end-state layout: eight earlier tasks moved every managed tool under
# its own name inside APP_DIR and retired the shared App/bin/. These read the
# installed application directory, not the repository, so they need a target
# that actually populates it (unlike every check above).
assert_cmd "one directory per managed tool" bash -c '
    for tool in go cmake cmakelib mise nvim ohmyzsh; do
        [ -d "${APP_DIR}/${tool}" ] || { echo "missing: ${tool}" >&2; exit 1; }
    done
'
assert_cmd "application root is not a dumping ground" bash -c '
    [ ! -e "${APP_DIR}/lib64" ] && [ ! -e "${APP_DIR}/share/nvim" ]
'
assert_cmd "no bare bin directory survives" bash -c '
    [ ! -e "${APP_DIR}/bin" ]
'
assert_cmd "the search path names exactly two APP_DIR entries" bash -c '
    [ "$(printf "%s\n" $PATH | tr ":" "\n" | grep -c "^${APP_DIR}/")" -eq 2 ] &&
    [ -d "${APP_DIR}/mise/bin" ] && [ -d "${APP_DIR}/nvim/bin" ]
'
