for target in "$HOME/.zshrc" \
              "$HOME/.config/nvim/init.vim" "$HOME/.config/kitty/kitty.conf"; do
    assert_cmd "is a symlink: $target"  test -L "$target"
    assert_cmd "resolves: $target"      test -e "$target"
done
assert_cmd "kitty parent dir created"   test -d "$HOME/.config/kitty"
assert_cmd "no stale zshrc_config link" test ! -e "$HOME/.zshrc_config"
