#!/bin/bash

set -e

CMAKE_VERSION=v3.30.1

setup() {
    check_if_command_is_installed make
    check_if_command_is_installed git

    install_dir=$(get_install_dir)
    pushd CMake
        git clean -xfd
        git checkout -- .
        git checkout ${CMAKE_VERSION}
        ./configure --prefix="${install_dir}" --parallel=12
        make -j 12
        make install
        git clean -xfd
        git checkout -- .
    popd
}

