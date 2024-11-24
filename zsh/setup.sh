#!/bin/bash

set -e

setup() {

    # apt install silversearcher-ag
    check_if_command_is_installed ag

    # apt install fzf
    check_if_command_is_installed fzf
    check_if_command_is_installed sed
    check_if_command_is_installed git
    check_if_command_is_installed zsh

    local ohmyzsh_path="$(pwd)"
    local user_bin_dir="$(get_user_bin_dir)"
    local cmlib_dir="$(git rev-parse --show-toplevel)/cmakelib"
    local zshrc_path="$HOME/.zshrc"
    local config_path="$HOME/.zshrc_config"

    rm -f zshrc config

    cp template/zshrc_template zshrc
    cp template/config_template config

    sed -i "s|___OHMYZSH_PROJECT_DIR___|${ohmyzsh_path}|" zshrc
    sed -i "s|___USER_BIN_DIR___|${user_bin_dir}|" zshrc
    sed -i "s|___CMAKELIB_DIR___|${cmlib_dir}|" config

    local muse_patch=$(pwd)/muse_theme.patch
    pushd ohmyzsh
        git clean -xfd .
        git checkout -- .
        git apply "${muse_patch}"
    popd

    rm -f "${zshrc_path}"
    rm -f "${config_path}"
    ln -s $(pwd)/zshrc "${zshrc_path}"
    ln -s $(pwd)/config "${config_path}"

}