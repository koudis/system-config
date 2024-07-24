#!/bin/bash

set -e

NVIM_VERSION=v0.10.0

setup() {
    check_if_command_is_installed cmake
    check_if_command_is_installed make
    check_if_command_is_installed git

    local vim_base_dir="$(git rev-parse --show-toplevel)/vim"

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

    rm -f init.vim
    cp template/init_template.vim init.vim

    sed -i "s|___VIM_BASE_DIR___|${vim_base_dir}|" init.vim

    mkdir -p $HOME/.config/nvim
    mkdir -p $HOME/.local/share/nvim/site/autoload/

    ln -s init.vim $HOME/.config/nvim/init.vim
    curl -fLo "${HOME}/.local/share/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

}