#!/bin/bash

set -e

check_install_dir() {    
    local install_dir="$1"
    if [[ $install_dir = "" ]] then
        echo "INSTALL_DIR is not specified"
        return 1
    fi
    return 0
}

check_if_command_installed() {
    local command_name="$1"
    which "$command_name" > /dev/null
    if ! [[ $? -eq 0 ]] then
        echo "Command '${command_name}' cannot be found!"
        exit 1
    fi
}

check_environment() {
    if [[ $INSTALL_DIR = ""]] then
        echo "IONSTALL_DIR is already set! Cannot continue."
        exit 1
    fi
}

set_install_dir() {
    INSTALL_DIR="$1"
    check_install_dir "${INSTALL_DIR}"
}

get_install_dir() {
    check_install_dir "${INSTALL_DIR}"
    echo "${INSTALL_DIR}"
}
