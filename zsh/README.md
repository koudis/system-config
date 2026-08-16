
# ZSH Configuration

Tools used:

- direnv
- wd
- fzf

Tools are declared in `[bootstrap.packages]` in `mise.toml` and installed by
`./setup`.

## How to configure

Run `./setup` from the repository root. It renders `zshrc`, links it into
`$HOME` and sets zsh as the login shell; no manual `chsh` is needed.