
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

## Migrating from a pre-split checkout

A checkout from before `./setup` was split into `./setup system` and `./setup`
needs three one-time steps on its first run under the new layout.

**1. The seventeen Flatpaks.** They used to install system-wide; they now
install in user scope (`APPS-R-10`), and the first `./setup` adds a second,
user-scope copy of each rather than adopting the system one. The old
system-scope copies become dead weight once the user-scope copies land.
Remove them with the exact identifiers below - not a glob, and not
`--unused`, because the system installation may hold other applications this
repository does not manage:

```bash
sudo flatpak uninstall --system \
  org.kicad.KiCad org.freecad.FreeCAD net.ankiweb.Anki md.obsidian.Obsidian \
  com.prusa3d.PrusaSlicer com.jgraph.drawio.desktop com.usebottles.bottles \
  org.texstudio.TeXstudio org.onlyoffice.desktopeditors org.openstreetmap.josm \
  com.axosoft.GitKraken org.kde.krita com.github.tchx84.Flatseal \
  org.gnome.Extensions com.mattjakeman.ExtensionManager cc.arduino.IDE2 \
  org.kde.tellico
```

These identifiers are declared once, in `mise.toml`'s `FLATPAK_APPS` - re-read
them from there rather than trusting this copy if the two ever disagree.

**2. `zsh/zshrc`.** It is gitignored, so a copy generated before fetched
runtime content moved out of the repository still names the old path, and
`[tasks.render]`'s overwrite guard refuses by name on the first run
afterwards. Delete the generated `zsh/zshrc` before re-running `./setup`; it
will be regenerated from the template.

**3. Paths the new layout leaves behind.** Setup installs into the new
locations; it never removes the old ones. Nothing reads any of the paths below
once this change lands, and deleting a path a previous version of this
repository created is exactly the decision `GEN-R-17` exists to refuse - so
they are left for you, and `git status` reporting the two in-repository ones
as untracked is expected. Do not add them back to `.gitignore`; that only
hides them.

In the repository:

- `_vendor/` - held cmakelib and Oh My Zsh before they moved to `$APP_DIR`.
- `vendor/` - the name `_vendor/` replaced in an earlier rename.

Under `$APP_DIR` (default `~/App`):

- `bin/` - the shared binary directory. mise now lives at `$APP_DIR/mise/bin`
  and the Neovim build installs to `$APP_DIR/nvim/bin`, so nothing writes here.
- `lib64/` and `share/nvim/` - the old Neovim install spilled across the
  application root, because its prefix was `$APP_DIR` itself rather than
  `$APP_DIR/nvim`. The same install also wrote `share/man`, `share/icons` and
  `share/applications`; look before removing those, since other software may
  have written there too.
- `mise/installs/` - where mise kept every tool before `MISE_INSTALLS_DIR`
  became `$APP_DIR` and each tool got a directory named after it.

Once you have confirmed you no longer need the old content, remove them
yourself. Every path is named in full below; do not substitute a glob:

```bash
rm -rf _vendor vendor
rm -rf "${APP_DIR:-$HOME/App}/bin" \
       "${APP_DIR:-$HOME/App}/lib64" \
       "${APP_DIR:-$HOME/App}/share/nvim" \
       "${APP_DIR:-$HOME/App}/mise/installs"
```

[mise]: https://mise.jdx.dev
