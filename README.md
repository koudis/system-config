
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
sudo -v
./setup
```

That is the whole procedure. `./setup` installs [mise] if it is missing and
then runs every task declared in `mise.toml`. Running it a second time changes
nothing.

Refresh the sudo credential first, as shown. Package installation and the login
shell change run as tasks, and mise interleaves task output, so a password
prompt appearing from inside a task is unprefixed and easy to miss among the
other lines.

Everything is installed under `$APP_DIR`, which defaults to `~/App`. Export a
different `APP_DIR` before running to install somewhere else.

Keep this repository **outside** `$APP_DIR`. The two locations must not
overlap: the repository holds configuration, templates and pins, while
`$APP_DIR` holds installed artifacts only, and rebuilding the environment means
deleting `$APP_DIR` and re-running `./setup`. A checkout inside `$APP_DIR`
would be deleted by that. `./setup` warns when it detects the overlap; it does
not move anything or change the default.

A single task can be run on its own by naming it, for example `./setup link`.
`./setup preview` reports what a run would change without changing it.

To add a tool, follow [docs/adding-a-new-tool.md](docs/adding-a-new-tool.md).

[mise]: https://mise.jdx.dev
