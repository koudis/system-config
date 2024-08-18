#!/bin/bash

set -e

setup() {
    mkdir -p $HOME/.config/alacritty
    rm -f $HOME/.config/alacritty/alacritty.toml
    ln -s $(pwd)/config.toml $HOME/.config/alacritty/alacritty.toml
}

