#!/bin/bash

set -e

setup() {
    check_if_command_is_installed cmake
    check_if_command_is_installed make
    check_if_command_is_installed git
    check_if_command_is_installed gettext
    check_if_command_is_installed gcc

    pushd neovim
        git clean -xfd .
        git checkout -- .
        install_dir=$(get_install_dir)
        make CMAKE_INSTALL_PREFIX="${install_dir}" CMAKE_BUILD_TYPE=RelWithDebInfo .
        make install
        git clean -xfd .
        git checkout -- .
    popd
}