#!/bin/bash

set -e

setup() {
    install_dir=$(get_install_dir)

    check_if_command_installed cmake
    check_if_command_installed make
    check_if_command_installed git
    pushd neovim
        mkdir -p _build
        pushd _build
            cmake -DCMAKE_INSTALL_PREFIX="${install_dir}" -DCMAKE_BUILD_TYPE=RelWithDebInfo ../
            make -j 12
            make install
        popd
        git clean -xfd .
        git checkout -- .
    popd
}