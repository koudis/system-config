#!/bin/bash

set -e

setup() {
    sudo apt install silversearcher-ag
    sudo apt install fzf

    local ohmyzsh_path=$(pwd)/ohmyzsh
    rm -f zshrc
    cp zshrc_template zshrc

    sed -i "s/___OHMYZSH_PATH___/${ohmyzsh_path}/" zshrc

    pushd ohmyzsh
        git clean -xfd .
        git checkout -- .
    popd
    ln -s $(pwd)/zshrc $HOME/.zshrc
}