#!/bin/bash

set -e

setup() {

    # apt install silversearcher-ag
    check_if_command_is_installed ag

    # apt install fzf
    check_if_command_is_installed fzf
    check_if_command_is_installed sed

    local ohmyzsh_path=$(pwd)
    local zshrc_path=$HOME/.zshrc

    rm -f zshrc
    cp template/zshrc_template zshrc

    sed -i "s|___OHMYZSH_PROJECT_DIR___|${ohmyzsh_path}|" zshrc

    pushd ohmyzsh
        git clean -xfd .
        git checkout -- .
    popd

    rm -f "${zshrc_path}"
    ln -s $(pwd)/zshrc "${zshrc_path}"
}