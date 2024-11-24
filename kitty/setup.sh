#!/bin/bash

set -e

setup() {
    check_if_command_is_installed kitty

    ln -s $(pwd)/kitty.conf ~/.config/kitty/kitty.conf 
}