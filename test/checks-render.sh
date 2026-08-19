# Rendered artifacts exist and carry no leftover placeholder.
assert_cmd "zshrc rendered"    test -f zsh/zshrc
assert_cmd "init.vim rendered" test -f vim/init.vim
assert_cmd "no unsubstituted tokens" \
    bash -c '! grep -rqE "___[A-Za-z0-9_]+___" zsh/zshrc vim/init.vim'
# The harness user is "tester", so any /home/h is a leftover literal from the
# old templates (the ghcup line) rather than the rendering root.
assert_cmd "no hardcoded username in rendered output" \
    bash -c '! grep -rq "/home/h" zsh/zshrc vim/init.vim'

# The placeholders must resolve to the directories the fetch task actually
# populates. Evaluating the assignments beats grepping for a path: it is the
# same resolution zsh performs, and it catches a token that renders to a
# syntactically fine but nonexistent location.
assert_cmd "ZSH and ZSH_CUSTOM resolve to populated directories" bash -c '
    eval "$(grep -E "^(ZSH_PROJECT_DIR|export ZSH|ZSH_CUSTOM)=" zsh/zshrc)"
    [[ -d $ZSH/lib && -d $ZSH_CUSTOM/themes && -d $ZSH_CUSTOM/plugins/zsh-autosuggestions ]]'
assert_cmd "ZSH_CUSTOM is the repository custom dir" bash -c '
    eval "$(grep -E "^ZSH_CUSTOM=" zsh/zshrc)"
    [[ $ZSH_CUSTOM == "$PWD/zsh/custom" ]]'

# GEN-A-7: mise reads MISE_DATA_DIR at process start, so `mise activate` cannot
# pick it up from mise.toml [env]. An interactive shell that does not export it
# itself silently installs into mise's default data directory instead of
# $APP_DIR/mise. Evaluated in a fresh process with both variables unset, so a
# commented-out or reordered export cannot pass.
assert_cmd "zshrc yields MISE_DATA_DIR under APP_DIR" bash -c '
    v=$(env -u APP_DIR -u MISE_DATA_DIR bash -c \
        "eval \"\$(grep -E \"^export (APP_DIR|MISE_DATA_DIR)=\" zsh/zshrc)\"; printf %s \"\$MISE_DATA_DIR\"")
    [[ $v == "$HOME/App/mise" ]]'
# Both line numbers must exist: with an empty operand [[ "" -lt 149 ]] is true,
# so a deleted export would otherwise satisfy the ordering test.
assert_cmd "MISE_DATA_DIR exported before mise is activated" bash -c '
    d=$(grep -n "^export MISE_DATA_DIR=" zsh/zshrc | head -1 | cut -d: -f1)
    a=$(grep -n "mise activate zsh"      zsh/zshrc | head -1 | cut -d: -f1)
    [[ -n $d && -n $a && $d -lt $a ]]'
# Same shape, same reason (GEN-A-7): MISE_INSTALLS_DIR is read at process
# start too, so it must be exported above activation as well.
assert_cmd "MISE_INSTALLS_DIR exported before mise is activated" bash -c '
    d=$(grep -n "^export MISE_INSTALLS_DIR=" zsh/zshrc | head -1 | cut -d: -f1)
    a=$(grep -n "mise activate zsh"           zsh/zshrc | head -1 | cut -d: -f1)
    [[ -n $d && -n $a && $d -lt $a ]]'

# Step 4a: the cmakelib exports moved to mise.toml [env], so neither the
# fragment nor its rendered output may come back.
assert_cmd "config_template gone"  test ! -f zsh/template/config_template
assert_cmd "no rendered zsh/config" test ! -f zsh/config
assert_cmd "no zsh-emitted CMLIB"  bash -c '! grep -rq CMLIB zsh/template/'
assert_cmd "template does not source the deleted fragment" \
    bash -c '! grep -rq "PROJECT_DIR}/config" zsh/template/zshrc_template'

assert_absent "GO_BIN_DIR gone"       "GO_BIN_DIR"   zsh/template/zshrc_template
assert_absent "USER_BIN_DIR gone"     "USER_BIN_DIR" zsh/template/zshrc_template
assert_absent "ghcup line gone"       "ghcup"        zsh/template/zshrc_template
assert_absent "no hardcoded username" "/home/h"      zsh/template/zshrc_template

# ZSH-R-4: the theme is a committed file in the custom directory, not a patch
# applied to a freshly fetched upstream tree.
assert_cmd "theme committed"   test -f zsh/custom/themes/muse.zsh-theme
assert_cmd "patch file gone"   test ! -f zsh/muse_theme.patch
assert_cmd "theme prompt is two lines" \
    bash -c '[[ $(sed -n 2p zsh/custom/themes/muse.zsh-theme) == *"FG[077]"* ]]'

assert_cmd "global config file exported before activation" bash -c '
    grep -q "^export MISE_GLOBAL_CONFIG_FILE=" zsh/zshrc &&
    [ "$(grep -n "^export MISE_GLOBAL_CONFIG_FILE=" zsh/zshrc | cut -d: -f1)" \
      -lt "$(grep -n "mise activate zsh" zsh/zshrc | cut -d: -f1)" ]
'
assert_cmd "global config file points at the pin registry" bash -c '
    grep -q "^export MISE_GLOBAL_CONFIG_FILE=\"$PWD/mise.toml\"" zsh/zshrc
'
assert_cmd "no unsubstituted placeholder" bash -c '! grep -q "___" zsh/zshrc'
