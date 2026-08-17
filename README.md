
# Koudis` System Config

System config repo to configure basics applications after fresh Linux install.

## List of managed tools

- CMake
- [CMakeLib]
- Go
- NeoVim
- ZSH
- Kitty
- Desktop applications, installed as Flatpaks from Flathub

One requirements document per entry lives in `docs/requirements/`.

[CMakeLib]: https://github.com/cmakelib/cmakelib

## Build and Install

```bash
sudo -v
./setup system
./setup
```

`./setup` installs [mise] if it is missing and then runs every task declared in
`mise.toml`. Running either command a second time changes nothing.

`./setup system` is the privileged half and is run once per machine. It installs
the distribution packages and sets the login shell, and it is the only command
here that elevates. `./setup` is the whole rest of the work and never elevates -
it refuses to start if the privileged half has not run, naming what is missing.

Refresh the sudo credential first, as shown, before `./setup system`. Package
installation and the login shell change run as tasks, and mise interleaves task
output, so a password prompt appearing from inside a task is unprefixed and easy
to miss among the other lines.

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

## Generated files

`zsh/zshrc` and `vim/init.vim` are generated from the templates beside them and
are not committed. Setup will not overwrite either one if its content differs
from what the template renders to: it stops and names the file instead, because
edits made directly to a generated file exist nowhere else. Put lasting changes
in `zsh/template/zshrc_template` or `vim/template/init_template.vim` and re-run.
An unchanged generated file is left untouched, so a repeat run stays a no-op.

To add a tool, follow [docs/adding-a-new-tool.md](docs/adding-a-new-tool.md).

[mise]: https://mise.jdx.dev
