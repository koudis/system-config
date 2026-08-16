
# Koudis` System Config

System config repo to configure basics applications after fresh Linux install.

## List of managed tools

- CMake
- [CMakeLib]
- NeoVim
- ZSH
- Kitty

[CMakeLib]: https://github.com/cmakelib/cmakelib

## Build and Install

```bash
./setup
```

That is the whole procedure. `./setup` installs [mise] if it is missing and
then runs every task declared in `mise.toml`. Running it a second time changes
nothing.

Everything is installed under `$APP_DIR`, which defaults to `~/App`. Export a
different `APP_DIR` before running to install somewhere else.

A single task can be run on its own by naming it, for example `./setup link`.
`./setup preview` reports what a run would change without changing it.

To add a tool, follow [docs/adding-a-new-tool.md](docs/adding-a-new-tool.md).

[mise]: https://mise.jdx.dev
