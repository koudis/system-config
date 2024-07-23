#!/bin/bash

set -e

NVIM_VERSION=v0.10.0

setup() {
    check_if_command_is_installed cmake
    check_if_command_is_installed make
    check_if_command_is_installed git

    pushd neovim
        git clean -xfd .
        git checkout -- .
        git checkout ${NVIM_VERSION}
        install_dir=$(get_install_dir)
        make CMAKE_INSTALL_PREFIX="${install_dir}" CMAKE_BUILD_TYPE=RelWithDebInfo .
        make CMAKE_INSTALL_PREFIX="${install_dir}" install
        git clean -xfd .
        git checkout -- .
    popd
}