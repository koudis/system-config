
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

Each tool is compiled, setup and installed separately by a `setup.sh <tools_name>` script.

The script install all dependencies to ~/Bin directory.

The toolname is a name of the containing directory in the git root.

For exmaple install Neovim run

```bash
./setup.sh vim
```

## 
